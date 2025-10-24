# Output Cleanup Demonstration
# This app shows different ways to clean up outputs and their effects

library(shiny)

cat("\n")
cat("==================================================================\n")
cat("OUTPUT CLEANUP DEMONSTRATION\n")
cat("==================================================================\n\n")

cat("This app demonstrates:\n")
cat("  1. Creating dynamic outputs\n")
cat("  2. Server-side cleanup (output <- NULL)\n")
cat("  3. UI cleanup (removeUI)\n")
cat("  4. The difference between them\n")
cat("  5. Memory leak prevention\n\n")

ui <- fluidPage(
  titlePanel("Output Cleanup Demo"),

  fluidRow(
    column(4,
      wellPanel(
        h4("Controls"),
        actionButton("create", "Create Output", class = "btn-success", width = "100%"),
        br(), br(),
        actionButton("set_null", "Set to NULL (Server Cleanup)", class = "btn-warning", width = "100%"),
        br(), br(),
        actionButton("remove_ui", "Remove UI Only (BAD!)", class = "btn-danger", width = "100%"),
        br(), br(),
        actionButton("full_cleanup", "Full Cleanup (Recommended)", class = "btn-primary", width = "100%"),
        br(), br(),
        actionButton("recreate_ui", "Recreate UI Element", class = "btn-info", width = "100%")
      ),
      wellPanel(
        h4("Execution Counter"),
        p("Watch how many times the render function executes:"),
        verbatimTextOutput("counter"),
        actionButton("reset_counter", "Reset Counter", width = "100%")
      )
    ),

    column(8,
      wellPanel(
        h4("Status"),
        verbatimTextOutput("status")
      ),
      hr(),
      h4("Output Container:"),
      div(
        id = "output-container",
        style = "border: 2px dashed #ccc; min-height: 100px; padding: 20px;",
        p(class = "text-muted", "Outputs will appear here")
      ),
      hr(),
      wellPanel(
        h4("What's Happening:"),
        uiOutput("explanation")
      )
    )
  )
)

server <- function(input, output, session) {
  # Counter for tracking render executions
  render_count <- reactiveVal(0)

  # Track whether output exists
  output_exists <- reactiveVal(FALSE)
  ui_exists <- reactiveVal(FALSE)

  # Display counter
  output$counter <- renderText({
    paste("Render executed:", render_count(), "times")
  })

  # Reset counter
  observeEvent(input$reset_counter, {
    render_count(0)
  })

  # Create output
  observeEvent(input$create, {
    cat("\n[CREATE] Creating dynamic output\n")

    # Insert UI element
    insertUI(
      selector = "#output-container",
      where = "afterBegin",
      ui = div(
        id = "dynamic-output-wrapper",
        class = "well",
        h4("Dynamic Output", style = "color: green;"),
        plotOutput("dynamic_plot"),
        verbatimTextOutput("dynamic_text")
      )
    )
    ui_exists(TRUE)

    # Create server-side outputs
    output$dynamic_plot <- renderPlot({
      count <- render_count() + 1
      render_count(count)
      cat(sprintf("[RENDER] dynamic_plot executing (count: %d) at %s\n",
                  count, format(Sys.time(), "%H:%M:%S")))

      plot(rnorm(100), main = paste("Render count:", count),
           col = "blue", pch = 16)
    })

    output$dynamic_text <- renderText({
      paste("Current time:", format(Sys.time(), "%H:%M:%S.%OS3"))
    })

    output_exists(TRUE)
    showNotification("Output created! Watch the counter increase on each re-render.",
                     type = "message", duration = 3)
  })

  # Set output to NULL (server cleanup only)
  observeEvent(input$set_null, {
    cat("\n[CLEANUP] Setting output to NULL (server-side cleanup)\n")

    output$dynamic_plot <- NULL
    output$dynamic_text <- NULL

    output_exists(FALSE)

    cat("[CLEANUP] Observers destroyed\n")
    cat("[CLEANUP] UI element still exists but shows nothing\n")

    showNotification(
      "Server observer destroyed! The UI element is still there but empty.",
      type = "warning",
      duration = 5
    )
  })

  # Remove UI only (THIS CREATES A MEMORY LEAK!)
  observeEvent(input$remove_ui, {
    cat("\n[BAD] Removing UI only - THIS CREATES A MEMORY LEAK!\n")

    removeUI("#dynamic-output-wrapper")
    ui_exists(FALSE)

    cat("[BAD] UI removed but observer still exists!\n")
    cat("[BAD] The observer will keep executing in the background!\n")
    cat("[BAD] Watch the counter keep increasing even though you can't see it!\n")

    showNotification(
      "UI removed but observer still running! Check console - MEMORY LEAK!",
      type = "error",
      duration = 10
    )
  })

  # Full cleanup (recommended)
  observeEvent(input$full_cleanup, {
    cat("\n[FULL CLEANUP] Destroying observer AND removing UI\n")

    # Server cleanup first
    output$dynamic_plot <- NULL
    output$dynamic_text <- NULL
    output_exists(FALSE)

    cat("[FULL CLEANUP] Observers destroyed\n")

    # Then UI cleanup
    removeUI("#dynamic-output-wrapper")
    ui_exists(FALSE)

    cat("[FULL CLEANUP] UI removed\n")
    cat("[FULL CLEANUP] Complete! No memory leaks.\n")

    showNotification(
      "Complete cleanup! Observer destroyed and UI removed.",
      type = "message",
      duration = 3
    )
  })

  # Recreate UI element
  observeEvent(input$recreate_ui, {
    cat("\n[RECREATE] Recreating UI element\n")

    insertUI(
      selector = "#output-container",
      where = "afterBegin",
      ui = div(
        id = "dynamic-output-wrapper",
        class = "well",
        h4("Dynamic Output", style = "color: green;"),
        plotOutput("dynamic_plot"),
        verbatimTextOutput("dynamic_text")
      )
    )
    ui_exists(TRUE)

    cat("[RECREATE] UI element recreated\n")
    cat("[RECREATE] If observer still exists, output will reappear!\n")

    showNotification(
      "UI recreated. If the observer still exists, output will reappear!",
      type = "info",
      duration = 3
    )
  })

  # Status display
  output$status <- renderText({
    paste0(
      "Output Observer: ", if(output_exists()) "EXISTS ✓" else "DESTROYED ✗", "\n",
      "UI Element: ", if(ui_exists()) "EXISTS ✓" else "REMOVED ✗", "\n",
      "\n",
      if (output_exists() && !ui_exists()) {
        "⚠️  WARNING: Observer exists but UI is gone - MEMORY LEAK!\n"
      } else if (!output_exists() && ui_exists()) {
        "ℹ️  UI exists but observer destroyed - Output will be empty\n"
      } else if (output_exists() && ui_exists()) {
        "✓ Both exist - Output is active\n"
      } else {
        "✓ Both cleaned up - No memory leaks\n"
      }
    )
  })

  # Explanation
  output$explanation <- renderUI({
    if (output_exists() && ui_exists()) {
      div(
        class = "alert alert-info",
        h5("Current State: Active Output"),
        tags$ul(
          tags$li("The observer is running and will re-execute when invalidated"),
          tags$li("The UI element is visible in the browser"),
          tags$li("Everything is working normally")
        )
      )
    } else if (!output_exists() && !ui_exists()) {
      div(
        class = "alert alert-success",
        h5("Current State: Fully Cleaned"),
        tags$ul(
          tags$li("The observer has been destroyed (no more execution)"),
          tags$li("The UI element has been removed"),
          tags$li("No memory leaks - perfect cleanup!")
        )
      )
    } else if (!output_exists() && ui_exists()) {
      div(
        class = "alert alert-warning",
        h5("Current State: Observer Destroyed, UI Exists"),
        tags$ul(
          tags$li("The observer has been destroyed"),
          tags$li("The UI element is still visible but empty"),
          tags$li("This is what happens when you do: output$x <- NULL"),
          tags$li("The output shows nothing because req(FALSE) is called")
        )
      )
    } else if (output_exists() && !ui_exists()) {
      div(
        class = "alert alert-danger",
        h5("Current State: MEMORY LEAK!"),
        tags$ul(
          tags$li(strong("The observer is still running in the background!")),
          tags$li("The UI element has been removed"),
          tags$li(strong("Watch the counter - it keeps increasing!")),
          tags$li("The observer generates values that can't be displayed"),
          tags$li(strong("This wastes memory and CPU - always clean server first!"))
        )
      )
    }
  })
}

cat("To run this demo:\n")
cat("  shinyApp(ui, server)\n\n")

cat("Try this sequence:\n")
cat("  1. Click 'Create Output' - see the plot appear\n")
cat("  2. Wait and watch the counter increase as the plot re-renders\n")
cat("  3. Click 'Remove UI Only (BAD!)' - UI disappears but counter keeps going!\n")
cat("  4. Click 'Recreate UI Element' - the output reappears!\n")
cat("  5. Click 'Full Cleanup' - everything stops properly\n\n")

cat("==================================================================\n\n")

# Uncomment to run:
# shinyApp(ui, server)
