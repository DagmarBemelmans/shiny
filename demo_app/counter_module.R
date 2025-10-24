# Counter Module UI
# This function creates the UI for a counter module
counterUI <- function(id, label = "Counter") {
  ns <- NS(id)

  tagList(
    h3(label),
    actionButton(ns("increment"), "Increment (+1)"),
    actionButton(ns("decrement"), "Decrement (-1)"),
    actionButton(ns("reset"), "Reset"),
    br(),
    br(),
    verbatimTextOutput(ns("value"))
  )
}

# Counter Module Server
# This function creates the server logic for a counter module
counterServer <- function(id, initial_value = 0) {
  moduleServer(
    id,
    function(input, output, session) {
      # Reactive value to store the counter
      count <- reactiveVal(initial_value)

      # Increment the counter
      observeEvent(input$increment, {
        count(count() + 1)
      })

      # Decrement the counter
      observeEvent(input$decrement, {
        count(count() - 1)
      })

      # Reset the counter
      observeEvent(input$reset, {
        count(initial_value)
      })

      # Render the current value
      output$value <- renderText({
        paste("Current value:", count())
      })

      # Return the reactive value (can be used by parent)
      return(count)
    }
  )
}
