# Reactive Graph Demonstration
# This file demonstrates how the reactive dependency graph is built and maintained

library(shiny)

# Enable reactive logging to see what's happening
# (You can view this with reactlog::reactlog_show())
options(shiny.reactlog = TRUE)

cat("\n")
cat("==================================================================\n")
cat("REACTIVE GRAPH DEMONSTRATION\n")
cat("==================================================================\n\n")

cat("This app demonstrates how Shiny builds and maintains the reactive graph.\n\n")

cat("The reactive structure:\n\n")
cat("  input$slider  ─────┐\n")
cat("                     │\n")
cat("                     ↓\n")
cat("              squared_value (reactive)\n")
cat("                     │\n")
cat("         ┌───────────┼───────────┐\n")
cat("         ↓           ↓           ↓\n")
cat("  output$value  output$squared  output$debug\n\n")

ui <- fluidPage(
  titlePanel("Reactive Graph Demo"),

  sidebarLayout(
    sidebarPanel(
      sliderInput("slider", "Value:", min = 1, max = 10, value = 5),
      hr(),
      h4("Instructions:"),
      p("Move the slider and watch the outputs update."),
      p("Open the R console to see trace messages."),
      p("The reactive expression caches the squared value.")
    ),

    mainPanel(
      h3("Outputs"),
      wellPanel(
        h4("Original Value:"),
        verbatimTextOutput("value")
      ),
      wellPanel(
        h4("Squared Value (from reactive):"),
        verbatimTextOutput("squared")
      ),
      wellPanel(
        h4("Debug Info:"),
        verbatimTextOutput("debug")
      ),
      hr(),
      h4("What's happening behind the scenes:"),
      tags$ol(
        tags$li("When you move the slider, input$slider changes"),
        tags$li("Shiny invalidates the squared_value reactive expression"),
        tags$li("Shiny invalidates all three outputs (they all depend on something that changed)"),
        tags$li("During the flush cycle, outputs re-execute in order"),
        tags$li("Each output that uses squared_value() causes it to execute (but only once due to caching)"),
        tags$li("New dependencies are registered for the next cycle")
      )
    )
  )
)

server <- function(input, output, session) {
  cat("\n=== SERVER FUNCTION STARTING ===\n\n")

  # Create a reactive expression that squares the input value
  # This demonstrates how reactive expressions cache their results
  squared_value <- reactive({
    val <- input$slider
    result <- val^2

    cat(sprintf("[REACTIVE] squared_value executing: %d^2 = %d\n", val, result))
    Sys.sleep(0.1)  # Simulate some computation time
    cat(sprintf("[REACTIVE] squared_value finished\n"))

    result
  })

  # Output 1: Display the original value
  output$value <- renderText({
    val <- input$slider
    cat(sprintf("[OUTPUT] value rendering: %d\n", val))

    paste("Original:", val)
  })

  # Output 2: Display the squared value (uses the reactive)
  output$squared <- renderText({
    cat("[OUTPUT] squared rendering (calling squared_value reactive)\n")
    sq <- squared_value()  # This registers a dependency!
    cat(sprintf("[OUTPUT] squared got value: %d\n", sq))

    paste("Squared:", sq)
  })

  # Output 3: Display debug info (also uses the reactive)
  output$debug <- renderText({
    cat("[OUTPUT] debug rendering (calling squared_value reactive)\n")
    val <- input$slider
    sq <- squared_value()  # This also registers a dependency!
    cat(sprintf("[OUTPUT] debug got value: %d\n", sq))

    paste0(
      "Value: ", val, "\n",
      "Squared: ", sq, "\n",
      "Square root of squared: ", sqrt(sq), "\n",
      "Time: ", format(Sys.time(), "%H:%M:%S")
    )
  })

  cat("\n=== SERVER FUNCTION SETUP COMPLETE ===\n")
  cat("Now waiting for reactive flushes...\n\n")
  cat("Dependency graph created:\n")
  cat("  input$slider -> squared_value (reactive) -> output$squared, output$debug\n")
  cat("  input$slider -> output$value\n\n")
}

# Uncomment to run the app:
# shinyApp(ui, server)

cat("\n")
cat("==================================================================\n")
cat("TO RUN THIS DEMO:\n")
cat("==================================================================\n")
cat("1. Uncomment the last line: shinyApp(ui, server)\n")
cat("2. Run this file\n")
cat("3. Watch the console output as you interact with the slider\n")
cat("4. Notice how squared_value only executes ONCE per flush cycle,\n")
cat("   even though it's called by TWO different outputs!\n")
cat("5. To see the reactive graph visually, run: reactlog::reactlog_show()\n")
cat("==================================================================\n\n")

# ============================================================================
# EXAMPLE CONSOLE OUTPUT
# ============================================================================
cat("\n")
cat("Expected console output when you move the slider:\n")
cat("────────────────────────────────────────────────────────────────\n")
cat("[OUTPUT] value rendering: 6\n")
cat("[OUTPUT] squared rendering (calling squared_value reactive)\n")
cat("[REACTIVE] squared_value executing: 6^2 = 36\n")
cat("[REACTIVE] squared_value finished\n")
cat("[OUTPUT] squared got value: 36\n")
cat("[OUTPUT] debug rendering (calling squared_value reactive)\n")
cat("[OUTPUT] debug got value: 36\n")
cat("────────────────────────────────────────────────────────────────\n\n")

cat("Notice:\n")
cat("  - squared_value executes only ONCE\n")
cat("  - But it's called by BOTH output$squared and output$debug\n")
cat("  - This is because reactive expressions CACHE their results!\n")
cat("  - The cache is invalidated when input$slider changes\n")
cat("  - Then it re-executes on the first call, and returns cached value for subsequent calls\n\n")

# ============================================================================
# DETAILED TRACE
# ============================================================================

cat("\n")
cat("==================================================================\n")
cat("DETAILED TRACE OF WHAT HAPPENS BEHIND THE SCENES\n")
cat("==================================================================\n\n")

cat("1. USER MOVES SLIDER\n")
cat("   ↓\n")
cat("   Browser sends: {slider: 6}\n")
cat("   ↓\n")
cat("   input$slider ReactiveVal$set(6) is called\n")
cat("   ↓\n")
cat("   input$slider calls .dependents$invalidate()\n")
cat("   ↓\n")
cat("   All contexts that depend on input$slider are invalidated:\n")
cat("     - output$value context\n")
cat("     - squared_value context\n")
cat("   ↓\n")
cat("   squared_value context invalidation cascades:\n")
cat("     - output$squared context (depends on squared_value)\n")
cat("     - output$debug context (depends on squared_value)\n")
cat("   ↓\n")
cat("   All four observers are now in the flush queue\n\n")

cat("2. FLUSH CYCLE BEGINS\n")
cat("   ↓\n")
cat("   output$value observer executes:\n")
cat("     - Creates new Context\n")
cat("     - Runs renderText function\n")
cat("     - Reads input$slider (registers dependency)\n")
cat("     - Returns 'Original: 6'\n")
cat("     - Sends to browser\n")
cat("   ↓\n")
cat("   output$squared observer executes:\n")
cat("     - Creates new Context\n")
cat("     - Runs renderText function\n")
cat("     - Calls squared_value()\n")
cat("       ↓\n")
cat("       squared_value sees it's invalidated, so executes:\n")
cat("         - Creates new Context\n")
cat("         - Runs reactive function\n")
cat("         - Reads input$slider (registers dependency)\n")
cat("         - Computes 6^2 = 36\n")
cat("         - Caches result\n")
cat("         - Returns 36\n")
cat("     - Gets 36 from squared_value\n")
cat("     - Returns 'Squared: 36'\n")
cat("     - Sends to browser\n")
cat("   ↓\n")
cat("   output$debug observer executes:\n")
cat("     - Creates new Context\n")
cat("     - Runs renderText function\n")
cat("     - Calls squared_value()\n")
cat("       ↓\n")
cat("       squared_value sees it's NOT invalidated, returns cached 36\n")
cat("         (NO RE-EXECUTION!)\n")
cat("     - Gets 36 from squared_value (cached)\n")
cat("     - Returns debug info\n")
cat("     - Sends to browser\n")
cat("   ↓\n")
cat("   Flush cycle complete\n\n")

cat("3. DEPENDENCY GRAPH AFTER FLUSH\n\n")

cat("   input$slider.dependents = {\n")
cat("     output$value:   <Context #789>,\n")
cat("     squared_value:  <Context #790>\n")
cat("   }\n\n")

cat("   squared_value.dependents = {\n")
cat("     output$squared: <Context #791>,\n")
cat("     output$debug:   <Context #792>\n")
cat("   }\n\n")

cat("   These contexts will be invalidated next time input$slider changes!\n\n")

cat("==================================================================\n\n")
