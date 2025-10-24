# What Happens When You Render an Output with Reactive Dependencies

This document explains Shiny's reactive programming system - how outputs track their dependencies, build the reactive graph, and automatically update when dependencies change.

## Overview

When you write something like:

```r
output$text <- renderText({
  paste("Count:", count())
})
```

Shiny automatically:
1. Detects that `output$text` depends on `count()`
2. Creates an observer that re-executes when `count()` changes
3. Manages the dependency graph
4. Handles invalidation and re-execution

Let's dive into how this magic works!

## The Key Players

### 1. Context - The Execution Environment

**Location:** `R/react.R:20`

A `Context` represents a single execution of reactive code:

```r
Context <- R6Class('Context',
  public = list(
    id = character(0),              # Unique ID for this execution
    .invalidated = FALSE,            # Has this been invalidated?
    .invalidateCallbacks = list(),   # Callbacks to run on invalidation

    run = function(func) {
      # Set this context as the current context
      env <- .getReactiveEnvironment()
      env$runWith(self, func)        # Run func with this context active
    },

    invalidate = function() {
      if (.invalidated) return()
      .invalidated <<- TRUE

      # Call all registered invalidation callbacks
      lapply(.invalidateCallbacks, function(func) {
        func()
      })
    },

    onInvalidate = function(func) {
      # Register a callback for when this context is invalidated
      if (.invalidated)
        func()  # Already invalidated, call immediately
      else
        .invalidateCallbacks <<- c(.invalidateCallbacks, func)
    }
  )
)
```

**What it does:**
- Provides an execution context for reactive code
- Tracks what's currently being evaluated
- Manages invalidation callbacks

### 2. Dependents - Tracking Who Depends on What

**Location:** `R/reactives.R:4`

The `Dependents` class manages the list of contexts that depend on a reactive value:

```r
Dependents <- R6Class('Dependents',
  public = list(
    .dependents = 'Map',    # Map of context ID -> context object

    register = function() {
      # Get the currently executing context
      ctx <- getCurrentContext()

      if (!.dependents$containsKey(ctx$id)) {
        # Store this context as a dependent
        .dependents$set(ctx$id, ctx)

        # When the context is invalidated, remove it from dependents
        ctx$onInvalidate(function() {
          .dependents$remove(ctx$id)
        })
      }
    },

    invalidate = function() {
      # Invalidate ALL contexts that depend on this
      lapply(.dependents$values(), function(ctx) {
        ctx$invalidate()
      })
    }
  )
)
```

**What it does:**
- Maintains a list of all contexts (observers/reactives) that depend on a value
- Registers new dependencies when reactive values are accessed
- Propagates invalidation to all dependents

### 3. ReactiveVal - A Single Reactive Value

**Location:** `R/reactives.R:71`

```r
ReactiveVal <- R6Class('ReactiveVal',
  private = list(
    value = NULL,
    dependents = NULL  # Dependents object
  ),
  public = list(
    initialize = function(value) {
      private$value <- value
      private$dependents <- Dependents$new()
    },

    get = function() {
      # THIS IS KEY: Register the current context as a dependent!
      private$dependents$register()
      return(private$value)
    },

    set = function(value) {
      if (identical(private$value, value)) {
        return(invisible(FALSE))
      }
      private$value <- value

      # Value changed - invalidate all dependents!
      private$dependents$invalidate()
      invisible(TRUE)
    }
  )
)
```

**What it does:**
- When you **read** a reactive value (`count()`), it registers the current context as dependent
- When you **write** a reactive value (`count(5)`), it invalidates all dependent contexts

### 4. Observable - Reactive Expressions

**Location:** `R/reactives.R:815`

An `Observable` is what you create with `reactive({ ... })`:

```r
Observable <- R6Class('Observable',
  public = list(
    .func = 'function',        # The reactive expression
    .dependents = 'Dependents',# Who depends on this reactive
    .invalidated = TRUE,       # Is the cached value stale?
    .value = NULL,             # Cached result

    getValue = function() {
      # Register caller as dependent on this observable
      .dependents$register()

      # If invalidated, re-execute the function
      if (.invalidated) {
        self$.updateValue()
      }

      return(.value)
    },

    .updateValue = function() {
      # Create a context for this execution
      ctx <- Context$new(.domain, .label, type = 'observable')

      # When this context gets invalidated, mark this observable as invalidated
      ctx$onInvalidate(function() {
        .invalidated <<- TRUE
        .dependents$invalidate()  # Invalidate downstream dependents
      })

      .invalidated <<- FALSE

      # Execute the function within this context
      ctx$run(function() {
        result <- .func()
        .value <<- result
      })
    }
  )
)
```

**What it does:**
- Caches the result of a reactive expression
- Automatically re-executes when dependencies change
- Acts as both a dependent (of reactive values) and a dependency (for observers)

### 5. Observer - Side Effects

**Location:** `R/reactives.R:1107`

An `Observer` is what you create with `observe({ ... })` or `observeEvent()`. **Outputs are observers too!**

```r
Observer <- R6Class('Observer',
  public = list(
    .func = 'function',
    .ctx = NULL,

    initialize = function(observerFunc) {
      .func <<- observerFunc

      # Schedule the first execution
      .createContext()$invalidate()
    },

    .createContext = function() {
      ctx <- Context$new(.domain, .label, type='observer')
      .ctx <<- ctx

      # When this context is invalidated, schedule a re-execution
      ctx$onInvalidate(function() {
        .ctx <<- NULL
        # Add this observer to the flush queue
        ctx$addPendingFlush(.priority)
      })

      # When flushed, run the observer function
      ctx$onFlush(function() {
        if (!.destroyed) {
          run()
        }
      })

      return(ctx)
    },

    run = function() {
      # Create a new context for this execution
      ctx <- .createContext()

      # Execute the observer function within this context
      ctx$run(.func)
    }
  )
)
```

**What it does:**
- Executes side-effect code
- Automatically re-executes when dependencies change
- Doesn't cache a return value (unlike reactive expressions)

### 6. Output Assignment - Creating the Observer

**Location:** `R/shiny.R:2229` and `R/shiny.R:1096`

When you write `output$text <- renderText({ ... })`:

```r
`$<-.shinyoutput` <- function(x, name, value) {
  name <- .subset2(x, 'ns')(name)  # Apply namespace
  .subset2(x, 'impl')$defineOutput(name, value, label)
  return(invisible(x))
}

# Inside the ShinySession class:
defineOutput = function(name, func, label) {
  # Extract the render function
  # ...

  # THIS IS THE KEY: Create an observer for this output!
  obs <- observe({
    # Send "recalculating" message to client
    private$sendMessage(recalculating = list(
      name = name, status = 'recalculating'
    ))

    # Execute the render function
    result <- func()  # This is where dependencies are registered!

    # Send the result to the client
    if (inherits(result, 'try-error')) {
      # Handle error
      private$invalidatedOutputErrors$set(name, error_info)
    } else {
      # Send value to client
      private$invalidatedOutputValues$set(name, result)
    }

    # Send "recalculated" message to client
    private$sendMessage(recalculating = list(
      name = name, status = 'recalculated'
    ))
  })

  # Store the observer
  private$.outputs[[name]] <- obs
}
```

**What happens:**
- Creates an `Observer` that wraps your render function
- The observer automatically executes during the first flush
- When it executes, any reactive values it reads register the observer as dependent

## The Complete Flow: Step by Step

Let's trace what happens with this code:

```r
count <- reactiveVal(0)

observeEvent(input$button, {
  count(count() + 1)
})

output$text <- renderText({
  paste("Count:", count())
})
```

### Initial Setup (When App Starts)

1. **`count <- reactiveVal(0)`**
   - Creates a `ReactiveVal` object
   - Initializes with value `0`
   - Creates an empty `Dependents` object

2. **`observeEvent(input$button, { ... })`**
   - Creates an `Observer` that depends on `input$button`
   - Executes once initially (or waits for first button click)

3. **`output$text <- renderText({ ... })`**
   - `defineOutput()` creates an `Observer` for this output
   - The observer is scheduled to execute on the first flush
   - **Not executed yet!**

### First Flush

1. **Reactive environment flushes pending observers**
   - The `output$text` observer is in the queue

2. **Observer execution begins**
   ```r
   ctx <- Context$new(label = "output$text")
   env$runWith(ctx, function() {
     # Execute the render function
     paste("Count:", count())
   })
   ```

3. **Inside the render function**
   - `count()` is called
   - `ReactiveVal$get()` is executed
   - **KEY**: `get()` calls `.dependents$register()`
   - `getCurrentContext()` returns the `output$text` context
   - The context is added to `count`'s dependents list

4. **Dependency registered!**
   ```
   count.dependents = {
     "ctx_123": <Context for output$text>
   }
   ```

5. **Result sent to browser**
   - "Count: 0" is sent to the client

### User Clicks Button

1. **`input$button` changes**
   - Button click count increments
   - `input$button`'s dependents are invalidated
   - The button observer is invalidated and scheduled to flush

2. **Observer executes**
   ```r
   count(count() + 1)
   ```

3. **Reading `count()`**
   - `count()` is called (to get current value)
   - Button observer is registered as dependent
   - Returns `0`

4. **Writing `count(1)`**
   - `ReactiveVal$set(1)` is called
   - Value is updated to `1`
   - **KEY**: `.dependents$invalidate()` is called
   - ALL dependents of `count` are invalidated

5. **Invalidation propagates**
   ```
   count.dependents.each(ctx => ctx.invalidate())
   ```
   - The `output$text` context is invalidated
   - Invalidation callback runs
   - Observer is scheduled for re-execution

6. **Flush cycle**
   - `output$text` observer re-executes
   - Creates a NEW context
   - Executes `paste("Count:", count())`
   - `count()` is called again
   - NEW context is registered as dependent
   - Returns `1`
   - "Count: 1" is sent to browser

## The Reactive Graph

At any moment, Shiny maintains a dependency graph:

```
                    ┌─────────────┐
                    │  count()    │
                    │ ReactiveVal │
                    └─────────────┘
                           ↓
                           ↓ (depends on)
                           ↓
             ┌─────────────┴─────────────┐
             ↓                           ↓
     ┌──────────────┐            ┌──────────────┐
     │ output$text  │            │ button obs   │
     │   Observer   │            │   Observer   │
     └──────────────┘            └──────────────┘
```

When `count` changes, the arrows tell Shiny what needs to be invalidated and re-executed.

## Key Insights

### 1. **Dependency Registration Happens at Read Time**

When you call `count()` inside a reactive context, that context is automatically registered as a dependent. No manual subscription needed!

### 2. **Contexts are Disposable**

Every execution creates a new `Context`. When that execution finishes, the old context is discarded. This prevents memory leaks.

### 3. **Invalidation is Separate from Execution**

When a reactive value changes:
- **Invalidation** happens immediately (marks contexts as stale)
- **Execution** happens later (during the flush cycle)

This allows Shiny to batch updates efficiently.

### 4. **The Current Context is Ambient State**

`getCurrentContext()` returns whatever context is currently executing. This is stored in the `ReactiveEnvironment`'s `.currentContext` field. When you call `count()`, it doesn't need to be told who's calling - it looks up the ambient context.

### 5. **Observers Schedule Themselves**

When an observer is invalidated, it adds itself to a priority queue. During the flush cycle, observers are executed in priority order.

### 6. **Reactive Expressions Cache**

Unlike observers, reactive expressions (`reactive({ ... })`) cache their results. They only re-execute when:
- They're invalidated, AND
- Someone calls them

This is lazy evaluation - if nobody needs the value, it doesn't compute it.

## The Flush Cycle

**Location:** `R/react.R:169`

```r
flush = function() {
  if (!hasPendingFlush()) return(FALSE)
  if (.inFlush) return(FALSE)  # Prevent re-entrance

  .inFlush <<- TRUE

  while (hasPendingFlush()) {
    ctx <- .pendingFlush$dequeue()  # Get highest priority
    ctx$executeFlushCallbacks()      # Run the observer
  }

  .inFlush <<- FALSE
}
```

The flush cycle:
1. Dequeues pending contexts (observers) by priority
2. Executes their flush callbacks (which run the observer function)
3. During execution, new dependencies may be registered
4. During execution, reactive values may change, invalidating more observers
5. Newly invalidated observers are added to the queue
6. Repeats until queue is empty

## Summary: The Magic Explained

When you write:

```r
output$text <- renderText({
  paste("Count:", count())
})
```

Behind the scenes:

1. An `Observer` is created for `output$text`
2. When the observer executes, a `Context` is created
3. This context becomes the "current context" (ambient state)
4. When `count()` is called, it looks up the current context
5. The current context is added to `count`'s dependents list
6. When `count` changes, it calls `.dependents$invalidate()`
7. All dependent contexts (including `output$text`) are invalidated
8. Invalidated observers are scheduled to re-execute
9. The flush cycle runs, re-executing the observer
10. A new context is created, and the cycle repeats

**The genius of this design:**
- No manual subscription/unsubscription
- Automatic dependency tracking
- Efficient batching of updates
- Clean separation between invalidation and execution
- Natural garbage collection of unused dependencies

This is why Shiny feels magical - the reactive system does all the bookkeeping automatically, allowing you to write declarative code that "just works"!
