# Module Cleanup Demonstration
# Shows proper patterns for cleaning up modules to prevent memory leaks

library(shiny)

cat("\n")
cat("==================================================================\n")
cat("MODULE CLEANUP DEMONSTRATION\n")
cat("==================================================================\n\n")

cat("This app demonstrates:\n")
cat("  1. Creating modules dynamically\n")
cat("  2. Manual module cleanup\n")
cat("  3. Automatic cleanup on session end\n")
cat("  4. Memory leak prevention\n")
cat("  5. Best practices for module lifecycle management\n\n")

# ============================================================================
# MODULE: Counter with proper cleanup
# ============================================================================

counterUI <- function(id, label = "Counter") {
  ns <- NS(id)

  tagList(
    div(
      class = "well",
      style = "background-color: #f0f8ff;",
      h4(label, style = "color: #2c3e50;"),
      fluidRow(
        column(4, actionButton(ns("increment"), "+1", width = "100%")),
        column(4, actionButton(ns("decrement"), "-1", width = "100%")),
        column(4, actionButton(ns("reset"), "Reset", width = "100%"))
      ),
      br(),
      verbatimTextOutput(ns("value")),
      tags$small(
        class = "text-muted",
        "Module ID: ", id
      )
    )
  )
}

counterServer <- function(id, initial_value = 0) {
  moduleServer(id, function(input, output, session) {
    cat(sprintf("\n[MODULE %s] Initializing\n", id))

    # Reactive value
    count <- reactiveVal(initial_value)
    execution_count <- reactiveVal(0)

    # Observer 1: Increment
    obs_increment <- observeEvent(input$increment, {
      new_val <- count() + 1
      count(new_val)
      cat(sprintf("[MODULE %s] Incremented to %d\n", id, new_val))
    })

    # Observer 2: Decrement
    obs_decrement <- observeEvent(input$decrement, {
      new_val <- count() - 1
      count(new_val)
      cat(sprintf("[MODULE %s] Decremented to %d\n", id, new_val))
    })

    # Observer 3: Reset
    obs_reset <- observeEvent(input$reset, {
      count(initial_value)
      cat(sprintf("[MODULE %s] Reset to %d\n", id, initial_value))
    })

    # Output: Display value
    output$value <- renderText({
      exec <- execution_count() + 1
      execution_count(exec)
      cat(sprintf("[MODULE %s] Rendering output (execution #%d)\n", id, exec))

      paste0(
        "Value: ", count(), "\n",
        "Renders: ", exec
      )
    })

    # Cleanup function
    cleanup <- function() {
      cat(sprintf("\n[MODULE %s] ========== CLEANUP STARTED ==========\n", id))

      # Destroy observers
      cat(sprintf("[MODULE %s] Destroying obs_increment\n", id))
      obs_increment$destroy()

      cat(sprintf("[MODULE %s] Destroying obs_decrement\n", id))
      obs_decrement$destroy()

      cat(sprintf("[MODULE %s] Destroying obs_reset\n", id))
      obs_reset$destroy()

      # Clean output
      cat(sprintf("[MODULE %s] Cleaning output\n", id))
      output$value <- NULL

      cat(sprintf("[MODULE %s] ========== CLEANUP COMPLETE ==========\n\n", id))
    }

    # Register automatic cleanup when session ends
    session$onEnded(function() {
      cat(sprintf("[MODULE %s] Session ending - triggering cleanup\n", id))
      cleanup()
    })

    cat(sprintf("[MODULE %s] Initialization complete\n\n", id))

    # Return API
    list(
      value = count,
      execution_count = execution_count,
      cleanup = cleanup
    )
  })
}

# ============================================================================
# APP
# ============================================================================

ui <- fluidPage(
  titlePanel("Module Cleanup Demonstration"),

  sidebarLayout(
    sidebarPanel(
      h4("Module Management"),

      actionButton("create_counter", "Create Counter", class = "btn-success", width = "100%"),
      br(), br(),

      conditionalPanel(
        condition = "output.has_modules",
        actionButton("cleanup_last", "Clean Up Last Module", class = "btn-warning", width = "100%"),
        br(), br(),
        actionButton("cleanup_all", "Clean Up All Modules", class = "btn-danger", width = "100%"),
        br(), br()
      ),

      hr(),

      h4("Console Output"),
      p("Watch the R console for detailed logging of module lifecycle events."),

      hr(),

      h4("Status"),
      verbatimTextOutput("status")
    ),

    mainPanel(
      h3("Active Modules"),
      div(id = "modules-container"),

      conditionalPanel(
        condition = "!output.has_modules",
        div(
          class = "well text-center",
          style = "margin-top: 20px;",
          icon("info-circle", class = "fa-3x"),
          h4("No modules active"),
          p("Click 'Create Counter' to create a module")
        )
      ),

      hr(),

      wellPanel(
        h4("How It Works"),
        tags$ol(
          tags$li("Each module creates 3 observers (increment, decrement, reset) and 1 output"),
          tags$li("The module returns a cleanup function that destroys all its observers"),
          tags$li("Manual cleanup: Call the cleanup function and remove the UI"),
          tags$li("Automatic cleanup: Registered with session$onEnded() - happens when app closes"),
          tags$li("Watch the console to see cleanup in action!")
        )
      ),

      wellPanel(
        h4("Memory Leak Demo"),
        p(strong("Try this to see the importance of cleanup:")),
        tags$ol(
          tags$li("Create a module"),
          tags$li("Click the buttons - watch console output"),
          tags$li("Clean up properly - observers are destroyed"),
          tags$li("Try interacting again - nothing happens (observers gone!)")
        ),
        div(
          class = "alert alert-warning",
          strong("Warning: "), "If you remove the UI without calling cleanup(), ",
          "the observers keep running in the background - memory leak!"
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Track active modules
  modules <- reactiveVal(list())
  next_id <- reactiveVal(1)

  # Has modules flag for conditional panel
  output$has_modules <- reactive({
    length(modules()) > 0
  })
  outputOptions(output, "has_modules", suspendWhenHidden = FALSE)

  # Create module
  observeEvent(input$create_counter, {
    current_id <- paste0("counter", next_id())
    next_id(next_id() + 1)

    cat("\n")
    cat("==================================================================\n")
    cat(sprintf("CREATING MODULE: %s\n", current_id))
    cat("==================================================================\n")

    # Insert UI
    insertUI(
      selector = "#modules-container",
      where = "beforeEnd",
      ui = div(
        id = paste0(current_id, "-wrapper"),
        counterUI(current_id, label = paste("Counter", next_id() - 1))
      )
    )

    # Create module server
    module_ref <- counterServer(current_id, initial_value = 0)

    # Store reference
    current_modules <- modules()
    current_modules[[current_id]] <- list(
      id = current_id,
      ref = module_ref
    )
    modules(current_modules)

    showNotification(
      paste("Module", current_id, "created!"),
      type = "message",
      duration = 2
    )
  })

  # Clean up last module
  observeEvent(input$cleanup_last, {
    current_modules <- modules()

    if (length(current_modules) == 0) {
      showNotification("No modules to clean up!", type = "warning")
      return()
    }

    # Get last module
    last_id <- names(current_modules)[length(current_modules)]
    module_info <- current_modules[[last_id]]

    cat("\n")
    cat("==================================================================\n")
    cat(sprintf("MANUAL CLEANUP: %s\n", last_id))
    cat("==================================================================\n")

    # Call cleanup function
    module_info$ref$cleanup()

    # Remove UI
    removeUI(paste0("#", last_id, "-wrapper"))

    # Remove from list
    current_modules[[last_id]] <- NULL
    modules(current_modules)

    showNotification(
      paste("Module", last_id, "cleaned up!"),
      type = "message",
      duration = 2
    )
  })

  # Clean up all modules
  observeEvent(input$cleanup_all, {
    current_modules <- modules()

    if (length(current_modules) == 0) {
      showNotification("No modules to clean up!", type = "warning")
      return()
    }

    cat("\n")
    cat("==================================================================\n")
    cat("CLEANING UP ALL MODULES\n")
    cat("==================================================================\n")

    # Clean up each module
    for (module_id in names(current_modules)) {
      module_info <- current_modules[[module_id]]

      # Call cleanup
      module_info$ref$cleanup()

      # Remove UI
      removeUI(paste0("#", module_id, "-wrapper"))
    }

    # Clear all
    modules(list())

    showNotification(
      "All modules cleaned up!",
      type = "message",
      duration = 2
    )
  })

  # Status display
  output$status <- renderText({
    current_modules <- modules()
    count <- length(current_modules)

    if (count == 0) {
      "Active modules: 0\n\nNo modules currently active."
    } else {
      status <- paste0(
        "Active modules: ", count, "\n\n",
        "Module IDs:\n"
      )

      for (module_id in names(current_modules)) {
        module_info <- current_modules[[module_id]]
        status <- paste0(
          status,
          "  - ", module_id,
          " (value: ", module_info$ref$value(),
          ", renders: ", module_info$ref$execution_count(), ")",
          "\n"
        )
      }

      status
    }
  })

  # Session end handler
  session$onEnded(function() {
    cat("\n")
    cat("==================================================================\n")
    cat("SESSION ENDING - AUTOMATIC CLEANUP\n")
    cat("==================================================================\n")
    cat("Note: All modules registered cleanup with session$onEnded()\n")
    cat("      They will be cleaned up automatically!\n")
    cat("==================================================================\n\n")

    # Modules will clean themselves up automatically via their
    # session$onEnded() registrations
  })
}

cat("To run this demo:\n")
cat("  shinyApp(ui, server)\n\n")

cat("Try this sequence:\n")
cat("  1. Create several counter modules\n")
cat("  2. Interact with them (increment, decrement)\n")
cat("  3. Watch the console - see render executions\n")
cat("  4. Click 'Clean Up Last Module'\n")
cat("  5. Watch console - see cleanup happening\n")
cat("  6. Try interacting with the removed module - it's gone!\n")
cat("  7. Create more modules\n")
cat("  8. Close the app - see automatic cleanup in console\n\n")

cat("==================================================================\n\n")

# Uncomment to run:
# shinyApp(ui, server)
