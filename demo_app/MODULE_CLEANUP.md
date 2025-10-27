# How to Clean Up a Shiny Module

This document explains how to properly clean up modules, which is more complex than cleaning up individual outputs because modules contain multiple reactive components.

## Understanding Module Lifecycle

### Modules Don't Have Their Own Domains

**Key Insight:** Modules share their parent session's reactive domain!

**Location:** `R/modules.R:190` and `R/shiny.R:806`

When you create a module:
```r
counterServer("counter1")
```

What happens:
1. `callModule()` calls `session$makeScope("counter1")`
2. A **child scope** (session proxy) is created
3. The child scope has the **same domain** as the parent session
4. Observers created in the module belong to the **parent session's domain**

```r
# Inside makeScope():
scope <- createSessionProxy(self,  # 'self' is the parent session
  input = .createReactiveValues(private$.input, readonly = TRUE, ns = ns),
  output = .createOutputWriter(self, ns = ns),
  # ... other properties with namespace wrapping
)
# Note: The domain is inherited from 'self' (parent session)
```

### Automatic Cleanup on Session End

**Location:** `R/reactives.R:1249` and `R/reactive-domains.R:117`

By default, observers are created with `autoDestroy = TRUE`:

```r
Observer <- R6Class('Observer',
  initialize = function(observerFunc, ..., autoDestroy = TRUE) {
    # ...
    setAutoDestroy(autoDestroy)
  }
)
```

When `autoDestroy = TRUE`:
- Observer registers a callback with `onReactiveDomainEnded()`
- When the domain (session) ends, the callback destroys the observer
- **All module observers are automatically destroyed when the parent session ends**

**Location:** `R/shiny.R:1069`

```r
wsClosed = function() {
  self$closed <- TRUE
  # Suspend all outputs
  for (output in private$.outputs) {
    output$suspend()
  }
  # Invoke all "ended" callbacks
  private$closedCallbacks$invoke(...)
}
```

When the session closes:
1. All outputs are suspended
2. All `onEnded` callbacks are invoked
3. Observers with `autoDestroy=TRUE` are destroyed
4. This includes all observers in all modules!

## The Challenge: Manual Module Cleanup

**Problem:** Modules don't expose their internal observers by default!

When you create a module:
```r
counterServer("counter1")
```

The observers are created inside the module function, but you have no references to them. They're hidden in the module's closure.

**Solutions:**

### Solution 1: Return Cleanup Function from Module (Recommended)

Make your module return a cleanup function:

```r
# Module definition
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Create reactive values
    count <- reactiveVal(0)

    # Create observers
    obs1 <- observeEvent(input$increment, {
      count(count() + 1)
    })

    obs2 <- observeEvent(input$decrement, {
      count(count() - 1)
    })

    # Create outputs
    output$value <- renderText({
      paste("Count:", count())
    })

    # Return cleanup function
    cleanup <- function() {
      message("Cleaning up counter module: ", id)

      # Destroy observers
      obs1$destroy()
      obs2$destroy()

      # Clean up outputs
      output$value <- NULL

      # Any other cleanup (close connections, etc.)
      # ...
    }

    # Return both value and cleanup function
    list(
      value = count,      # Reactive value for parent to use
      cleanup = cleanup   # Cleanup function
    )
  })
}

# Usage
server <- function(input, output, session) {
  counter1 <- counterServer("counter1")

  observeEvent(input$remove_counter, {
    # Clean up the module
    counter1$cleanup()
  })
}
```

### Solution 2: Use a Reactive Domain for Each Module (Advanced)

Create a mock domain for each module that you can end independently:

```r
library(shiny)

# Helper to create an endable domain
createModuleDomain <- function(parent_session) {
  callbacks <- Callbacks$new()
  ended <- FALSE

  domain <- list(
    onEnded = function(callback) {
      callbacks$register(callback)
    },
    isEnded = function() {
      ended
    },
    end = function() {
      if (!ended) {
        ended <<- TRUE
        callbacks$invoke()
      }
    },
    # Forward other domain methods to parent
    reactlog = function(...) parent_session$reactlog(...),
    incrementBusyCount = function() parent_session$incrementBusyCount(),
    decrementBusyCount = function() parent_session$decrementBusyCount()
  )

  class(domain) <- "MockDomain"
  domain
}

# Module with custom domain
counterServer <- function(id, parent_session = getDefaultReactiveDomain()) {
  # Create a custom domain for this module
  module_domain <- createModuleDomain(parent_session)

  moduleServer(id, function(input, output, session) {
    # Create observers with the custom domain
    # Note: This requires manually specifying domain parameter
    obs1 <- observe(domain = module_domain, {
      # Observer logic
    })

    output$value <- renderText({
      # Output logic
    })

    # Return the domain so parent can end it
    list(
      domain = module_domain
    )
  })
}

# Usage
server <- function(input, output, session) {
  counter1 <- counterServer("counter1")

  observeEvent(input$remove_counter, {
    # End the module's domain - destroys all observers
    counter1$domain$end()
  })
}
```

**Note:** This is advanced and requires careful management. The recommended approach is Solution 1.

### Solution 3: Store Observers in Session userData

Use `session$userData` to store module observers for later cleanup:

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    count <- reactiveVal(0)

    # Create observers
    obs1 <- observeEvent(input$increment, {
      count(count() + 1)
    })

    obs2 <- observeEvent(input$decrement, {
      count(count() - 1)
    })

    # Store observers in userData (shared with parent)
    parent <- session$parent  # Access parent session from module
    if (is.null(parent$userData$moduleObservers)) {
      parent$userData$moduleObservers <- list()
    }
    parent$userData$moduleObservers[[id]] <- list(
      obs1 = obs1,
      obs2 = obs2
    )

    # Create output
    output$value <- renderText({
      paste("Count:", count())
    })

    return(count)
  })
}

# Usage
server <- function(input, output, session) {
  counter1_value <- counterServer("counter1")

  observeEvent(input$remove_counter, {
    # Access stored observers
    observers <- session$userData$moduleObservers[["counter1"]]

    if (!is.null(observers)) {
      # Destroy each observer
      observers$obs1$destroy()
      observers$obs2$destroy()

      # Clean up output (use namespaced ID)
      output[["counter1-value"]] <- NULL

      # Remove from userData
      session$userData$moduleObservers[["counter1"]] <- NULL
    }
  })
}
```

### Solution 4: Use `autoDestroy = FALSE` and Manual Management

Create observers with `autoDestroy = FALSE` and manage their lifecycle manually:

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    count <- reactiveVal(0)

    # Create observer with autoDestroy = FALSE
    obs <- observe(autoDestroy = FALSE, {
      # This observer won't be destroyed when session ends!
      # You MUST destroy it manually
    })

    # Return observer for manual management
    list(
      value = count,
      observer = obs
    )
  })
}

# Usage
server <- function(input, output, session) {
  counter1 <- counterServer("counter1")

  # IMPORTANT: Register cleanup when session ends
  onSessionEnded(function() {
    counter1$observer$destroy()
  })

  observeEvent(input$remove_counter, {
    # Manual cleanup
    counter1$observer$destroy()
  })
}
```

**Warning:** Using `autoDestroy = FALSE` is dangerous! You must ensure cleanup happens or you'll have memory leaks.

## Complete Example: Module with Cleanup

Here's a complete, production-ready example:

```r
library(shiny)

# ============================================================================
# MODULE DEFINITION
# ============================================================================

counterUI <- function(id, label = "Counter") {
  ns <- NS(id)
  tagList(
    h3(label),
    actionButton(ns("increment"), "Increment"),
    actionButton(ns("decrement"), "Decrement"),
    actionButton(ns("reset"), "Reset"),
    verbatimTextOutput(ns("value"))
  )
}

counterServer <- function(id, initial_value = 0) {
  moduleServer(id, function(input, output, session) {
    # Reactive value
    count <- reactiveVal(initial_value)

    # Observers
    obs_increment <- observeEvent(input$increment, {
      count(count() + 1)
    })

    obs_decrement <- observeEvent(input$decrement, {
      count(count() - 1)
    })

    obs_reset <- observeEvent(input$reset, {
      count(initial_value)
    })

    # Output
    output$value <- renderText({
      paste("Current value:", count())
    })

    # Cleanup function
    cleanup <- function() {
      message("Cleaning up counter module: ", id)

      # Destroy all observers
      obs_increment$destroy()
      obs_decrement$destroy()
      obs_reset$destroy()

      # Clean up output
      output$value <- NULL

      # Any other cleanup (e.g., close database connections)
      # ...

      message("Counter module cleaned up: ", id)
    }

    # Register automatic cleanup when session ends
    session$onEnded(cleanup)

    # Return API: reactive value and cleanup function
    list(
      value = count,
      cleanup = cleanup
    )
  })
}

# ============================================================================
# APP
# ============================================================================

ui <- fluidPage(
  titlePanel("Module Cleanup Demo"),

  fluidRow(
    column(4,
      wellPanel(
        h4("Module Management"),
        actionButton("create", "Create Counter Module"),
        actionButton("cleanup", "Clean Up Counter Module"),
        br(), br(),
        verbatimTextOutput("status")
      )
    ),
    column(8,
      div(id = "module-container")
    )
  )
)

server <- function(input, output, session) {
  # Store module reference
  counter_module <- reactiveVal(NULL)

  # Create module
  observeEvent(input$create, {
    # Check if module already exists
    if (!is.null(counter_module())) {
      showNotification("Module already exists!", type = "warning")
      return()
    }

    # Insert UI
    insertUI(
      selector = "#module-container",
      where = "afterBegin",
      ui = div(
        id = "counter-wrapper",
        wellPanel(counterUI("counter1", "Dynamic Counter"))
      )
    )

    # Create server module
    module_ref <- counterServer("counter1", initial_value = 0)

    # Store reference
    counter_module(module_ref)

    showNotification("Module created!", type = "message")
  })

  # Clean up module
  observeEvent(input$cleanup, {
    module_ref <- counter_module()

    if (is.null(module_ref)) {
      showNotification("No module to clean up!", type = "warning")
      return()
    }

    # Call cleanup function
    module_ref$cleanup()

    # Remove UI
    removeUI("#counter-wrapper")

    # Clear reference
    counter_module(NULL)

    showNotification("Module cleaned up!", type = "message")
  })

  # Status display
  output$status <- renderText({
    if (is.null(counter_module())) {
      "Status: No module\n\nClick 'Create Counter Module' to start."
    } else {
      paste0(
        "Status: Module active\n",
        "Current value: ", counter_module()$value(), "\n\n",
        "Click 'Clean Up Counter Module' to destroy it."
      )
    }
  })

  # Automatic cleanup when session ends
  session$onEnded(function() {
    if (!is.null(counter_module())) {
      message("Session ending - cleaning up module")
      counter_module()$cleanup()
    }
  })
}

shinyApp(ui, server)
```

## What Gets Cleaned Up

When you clean up a module, you should clean up:

### 1. Observers

```r
observer <- observeEvent(input$button, { ... })

# Later:
observer$destroy()
```

### 2. Outputs

```r
output$text <- renderText({ ... })

# Later:
output$text <- NULL
```

### 3. Reactive Expressions

Reactive expressions don't need explicit cleanup - they're garbage collected when no longer referenced. But if they depend on heavy resources, you might want to break the dependency chain:

```r
# Break dependency by setting to NULL
heavy_data <- NULL
```

### 4. Custom Resources

```r
# Close database connections
DBI::dbDisconnect(con)

# Close file handles
close(file_handle)

# Cancel background jobs
future::cancel(future_obj)

# Clear large objects
rm(large_data)
gc()
```

## Memory Leak Scenarios

### Leak 1: UI Removed but Module Not Cleaned

```r
# BAD!
removeUI("#counter-wrapper")
# Module observers still running - MEMORY LEAK!

# GOOD
counter_module$cleanup()  # Clean observers first
removeUI("#counter-wrapper")  # Then remove UI
```

### Leak 2: autoDestroy = FALSE Without Cleanup

```r
# BAD!
observe(autoDestroy = FALSE, {
  # This will NEVER be destroyed automatically!
})

# GOOD
obs <- observe(autoDestroy = FALSE, {
  # Observer logic
})

session$onEnded(function() {
  obs$destroy()  # Ensure cleanup
})
```

### Leak 3: Circular References

```r
# BAD!
module_obj <- list()
module_obj$cleanup <- function() {
  # References module_obj - circular reference!
  module_obj$value <- NULL
}

# GOOD - use local environment
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Local variables captured in closure
    count <- reactiveVal(0)
    obs <- observeEvent(...)

    cleanup <- function() {
      # References local variables, not self
      obs$destroy()
    }

    list(value = count, cleanup = cleanup)
  })
}
```

## Best Practices

### 1. Always Return a Cleanup Function

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # ... module logic ...

    cleanup <- function() {
      # Cleanup logic
    }

    return(list(
      # ... exported API ...
      cleanup = cleanup
    ))
  })
}
```

### 2. Register Automatic Cleanup

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    cleanup <- function() { ... }

    # Automatic cleanup when session ends
    session$onEnded(cleanup)

    return(list(..., cleanup = cleanup))
  })
}
```

### 3. Document Cleanup Requirements

```r
#' Counter Module Server
#'
#' @return A list containing:
#'   - value: Reactive value with current count
#'   - cleanup: Function to call for manual cleanup
#'
#' @section Cleanup:
#' The module automatically cleans up when the session ends.
#' For manual cleanup before session end, call the returned
#' cleanup function:
#' \code{module_ref$cleanup()}
#'
#' @export
counterServer <- function(id) { ... }
```

### 4. Test Cleanup

```r
# Use testServer to verify cleanup
test_that("counterServer cleans up properly", {
  testServer(counterServer, args = list(id = "test"), {
    # Interact with module
    session$setInputs(increment = 1)

    # Call cleanup
    cleanup()

    # Verify cleanup happened
    # (observers destroyed, outputs cleaned, etc.)
  })
})
```

## Summary

**Key Points:**

1. **Modules share the parent session's domain** - no separate lifecycle by default
2. **Automatic cleanup happens when session ends** - via `autoDestroy = TRUE`
3. **For manual cleanup, return a cleanup function** from your module
4. **Always clean observers before removing UI** to prevent memory leaks
5. **Register cleanup with `session$onEnded()`** for safety

**Pattern to follow:**

```r
myModuleServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    # 1. Create resources
    obs1 <- observeEvent(...)
    obs2 <- observeEvent(...)
    output$x <- renderText(...)

    # 2. Create cleanup function
    cleanup <- function() {
      obs1$destroy()
      obs2$destroy()
      output$x <- NULL
      # ... other cleanup ...
    }

    # 3. Register automatic cleanup
    session$onEnded(cleanup)

    # 4. Return API with cleanup
    list(
      # ... exported API ...
      cleanup = cleanup
    )
  })
}
```

This ensures proper resource management and prevents memory leaks!
