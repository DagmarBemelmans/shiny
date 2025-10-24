# How to Manually Clean Up Shiny Outputs

This document explains how to remove outputs from a Shiny session, as if they were never there.

## The Problem

When you create an output:

```r
output$myplot <- renderPlot({
  plot(cars)
})
```

Shiny creates an `Observer` object that:
- Tracks reactive dependencies
- Re-executes when dependencies change
- Sends results to the browser
- Consumes memory and processing time

Sometimes you want to completely remove an output, stopping it from executing and cleaning up resources.

## The Solutions

### Method 1: Set Output to NULL (Recommended)

**Location:** `R/shiny.R:1111`

The standard way to clean up an output is to set it to `NULL`:

```r
# Remove the output
output$myplot <- NULL
```

**What happens behind the scenes:**

1. `defineOutput()` is called with `func = NULL`
2. The old observer is destroyed:
   ```r
   if (!is.null(private$.outputs[[name]])) {
     private$.outputs[[name]]$destroy()  # Destroys old observer
   }
   ```
3. A special `missingOutput` function is assigned:
   ```r
   if (is.null(func)) {
     func <- missingOutput  # Special function that cancels output
   }
   ```
4. A new observer is created that runs `missingOutput`
5. `missingOutput` is defined as:
   ```r
   missingOutput <- function(...) req(FALSE)
   ```
6. `req(FALSE)` cancels the output, clearing it from the browser

**Result:**
- Old observer is destroyed (no more re-execution)
- New observer shows nothing in the browser
- Output element in the UI still exists but is empty

**Example:**

```r
ui <- fluidPage(
  actionButton("create", "Create Plot"),
  actionButton("remove", "Remove Plot"),
  plotOutput("myplot")
)

server <- function(input, output, session) {
  observeEvent(input$create, {
    output$myplot <- renderPlot({
      plot(cars)
    })
  })

  observeEvent(input$remove, {
    # Clean up the output
    output$myplot <- NULL
  })
}
```

### Method 2: Remove the UI Element (Additional Cleanup)

If you also want to remove the DOM element from the page:

```r
# Remove the server-side output
output$myplot <- NULL

# Remove the client-side DOM element
removeUI(selector = "#myplot")
```

**What happens:**

1. Setting `output$myplot <- NULL` destroys the observer on the server
2. `removeUI("#myplot")` sends a message to the browser
3. JavaScript removes the element with id "myplot" from the DOM

**Complete example:**

```r
ui <- fluidPage(
  actionButton("create", "Create Plot"),
  actionButton("remove", "Remove Plot"),
  div(id = "plot-container",
    plotOutput("myplot")
  )
)

server <- function(input, output, session) {
  observeEvent(input$create, {
    # Recreate the UI element if needed
    insertUI(
      selector = "#plot-container",
      where = "afterBegin",
      ui = plotOutput("myplot")
    )

    # Create the output
    output$myplot <- renderPlot({
      plot(cars)
    })
  })

  observeEvent(input$remove, {
    # Clean up the server-side observer
    output$myplot <- NULL

    # Remove the UI element from the DOM
    removeUI(selector = "#myplot")
  })
}
```

### Method 3: Direct Observer Destruction (Advanced/Not Recommended)

**This is for understanding only - not recommended for normal use!**

Outputs are stored in `private$.outputs` as `Observer` objects. Each observer has a `destroy()` method.

**Location:** `R/reactives.R:1296`

```r
Observer$destroy = function() {
  if (.destroyed) return()

  suspend()              # Stop execution
  .destroyed <<- TRUE    # Mark as destroyed

  if (!is.null(.ctx)) {
    .ctx$invalidate()    # Invalidate current context
  }
}
```

**Theoretically**, you could access and destroy observers directly, but:
- `.outputs` is private to the session object
- There's no public API to access it
- The recommended way is to use `output$name <- NULL`

## What Actually Happens When You Destroy an Output

Let's trace the complete cleanup process:

### Before Cleanup

```
Session state:
  private$.outputs = {
    "myplot": <Observer #123>
  }

Observer #123:
  .func = <renderPlot function>
  .ctx = <Context #456>
  .destroyed = FALSE
  .invalidateCallbacks = [...]

Dependency Graph:
  input$data -> output$myplot
```

### During `output$myplot <- NULL`

```
1. defineOutput("myplot", NULL) is called
   ↓
2. Check if output exists:
   if (!is.null(private$.outputs[["myplot"]])) {  # TRUE
     private$.outputs[["myplot"]]$destroy()       # Call destroy()
   }
   ↓
3. Observer$destroy() executes:
   - suspend() is called (stops execution)
   - .destroyed = TRUE
   - .ctx$invalidate() (invalidate current context)
   - Invalidation callbacks are cleared
   ↓
4. func = missingOutput is assigned
   ↓
5. NEW Observer is created:
   - Wraps missingOutput function
   - On execution, calls req(FALSE)
   - req(FALSE) cancels the output
   ↓
6. New observer is stored:
   private$.outputs[["myplot"]] = <new Observer>
```

### After Cleanup

```
Session state:
  private$.outputs = {
    "myplot": <Observer #789>  # NEW observer
  }

Old Observer #123:
  .destroyed = TRUE
  (Can be garbage collected)

New Observer #789:
  .func = missingOutput
  On execution: req(FALSE) -> output canceled

Dependency Graph:
  (output$myplot no longer depends on input$data)

Browser:
  Output element exists but is empty/hidden
```

## Important Distinctions

### Setting to NULL vs Overwriting

**Setting to NULL:**
```r
output$myplot <- NULL
```
- Destroys the old observer
- Creates a new observer that shows nothing
- Clears the output in the browser

**Overwriting with a new render function:**
```r
output$myplot <- renderPlot({ plot(iris) })
```
- Destroys the old observer
- Creates a new observer with different logic
- Shows new output in the browser

Both destroy the old observer! The difference is what replaces it.

### Server Cleanup vs UI Cleanup

**Server cleanup (`output$x <- NULL`):**
- Stops the observer from executing
- Frees up server resources
- The UI element still exists (just empty)

**UI cleanup (`removeUI()`):**
- Removes the DOM element from the browser
- Doesn't affect the server-side observer
- Always use BOTH for complete cleanup!

## Best Practices

### 1. Always Set to NULL Before Removing UI

```r
# CORRECT
output$myplot <- NULL   # Clean server first
removeUI("#myplot")     # Then remove UI

# INCORRECT (leaves observer running)
removeUI("#myplot")     # Only removes UI, observer still exists!
```

### 2. Clean Up Dynamic Outputs

If you're creating outputs dynamically, clean them up when done:

```r
observeEvent(input$add, {
  output_id <- paste0("plot_", input$add)

  insertUI(
    selector = "#container",
    ui = plotOutput(output_id)
  )

  output[[output_id]] <- renderPlot({
    plot(rnorm(100))
  })
})

observeEvent(input$clear, {
  # Get all dynamic output IDs
  output_ids <- paste0("plot_", seq_len(input$add))

  # Clean each one
  for (id in output_ids) {
    output[[id]] <- NULL        # Server cleanup
    removeUI(paste0("#", id))   # UI cleanup
  }
})
```

### 3. Use renderUI for Conditional Outputs

Instead of manually creating/destroying outputs, use conditional rendering:

```r
# MANUAL APPROACH (more complex)
observeEvent(input$show, {
  if (input$show) {
    output$plot <- renderPlot({ plot(cars) })
  } else {
    output$plot <- NULL
  }
})

# BETTER APPROACH (simpler)
output$plot <- renderPlot({
  req(input$show)  # Only render if show is TRUE
  plot(cars)
})
```

## Memory Leak Warning

**IMPORTANT:** If you remove the UI element without cleaning the output, the observer keeps running!

```r
# MEMORY LEAK!
removeUI("#myplot")
# Observer still exists and will try to execute
# It will generate values that can't be sent anywhere
# Memory and CPU are wasted!

# CORRECT
output$myplot <- NULL   # Stop the observer
removeUI("#myplot")     # Remove the UI
```

## Complete Example: Dynamic Output Management

```r
library(shiny)

ui <- fluidPage(
  titlePanel("Output Cleanup Demo"),

  actionButton("create", "Create Output"),
  actionButton("cleanup_server", "Cleanup Server Only"),
  actionButton("cleanup_full", "Full Cleanup (Server + UI)"),
  actionButton("recreate_ui", "Recreate UI"),

  hr(),
  div(id = "output-container")
)

server <- function(input, output, session) {

  observeEvent(input$create, {
    # Create UI element
    insertUI(
      selector = "#output-container",
      where = "afterBegin",
      ui = div(
        id = "plot-wrapper",
        h4("Dynamic Plot"),
        plotOutput("dynamic_plot")
      )
    )

    # Create server output
    output$dynamic_plot <- renderPlot({
      # This will keep executing until destroyed
      message("Rendering dynamic_plot at ", Sys.time())
      plot(rnorm(100))
    })

    showNotification("Output created", type = "message")
  })

  observeEvent(input$cleanup_server, {
    # Server cleanup only
    output$dynamic_plot <- NULL
    showNotification("Server observer destroyed (UI still visible but empty)", type = "warning")
  })

  observeEvent(input$cleanup_full, {
    # Full cleanup
    output$dynamic_plot <- NULL      # Destroy observer
    removeUI("#plot-wrapper")        # Remove UI
    showNotification("Full cleanup complete", type = "message")
  })

  observeEvent(input$recreate_ui, {
    # Recreate just the UI (without recreating the output)
    insertUI(
      selector = "#output-container",
      where = "afterBegin",
      ui = div(
        id = "plot-wrapper",
        h4("Dynamic Plot"),
        plotOutput("dynamic_plot")
      )
    )

    showNotification("UI recreated (will show previous output if it exists)", type = "message")
  })
}

shinyApp(ui, server)
```

## Summary

**To clean up an output completely:**

1. **Set to NULL:** `output$myplot <- NULL`
   - Destroys the observer
   - Stops reactive execution
   - Clears browser output

2. **Remove UI (optional):** `removeUI("#myplot")`
   - Removes DOM element
   - Frees browser memory

3. **Both together for complete cleanup:**
   ```r
   output$myplot <- NULL
   removeUI("#myplot")
   ```

**Remember:**
- Setting to `NULL` replaces the observer with one that shows nothing
- The old observer is destroyed and can be garbage collected
- Always clean server-side before removing UI elements
- Dynamic outputs need explicit cleanup to prevent memory leaks

This is how you make an output disappear "as if it wasn't there to begin with"!
