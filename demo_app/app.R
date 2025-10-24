# Simple Shiny App with Modules Demo
# This app demonstrates how to use Shiny modules to create reusable components

library(shiny)

# Source the counter module
source("counter_module.R")

# Define UI
ui <- fluidPage(
  titlePanel("Shiny Module Demo - Counter App"),

  sidebarLayout(
    sidebarPanel(
      h4("About this app"),
      p("This app demonstrates the use of Shiny modules."),
      p("Each counter below is an independent instance of the same module."),
      p("Modules help organize code and make components reusable.")
    ),

    mainPanel(
      fluidRow(
        column(6,
          wellPanel(
            counterUI("counter1", "Counter 1")
          )
        ),
        column(6,
          wellPanel(
            counterUI("counter2", "Counter 2 (starts at 10)")
          )
        )
      ),
      fluidRow(
        column(12,
          wellPanel(
            counterUI("counter3", "Counter 3 (starts at -5)")
          )
        )
      ),
      hr(),
      h4("Sum of all counters:"),
      verbatimTextOutput("total")
    )
  )
)

# Define server logic
server <- function(input, output, session) {
  # Create three counter module instances with different initial values
  counter1_value <- counterServer("counter1", initial_value = 0)
  counter2_value <- counterServer("counter2", initial_value = 10)
  counter3_value <- counterServer("counter3", initial_value = -5)

  # Calculate and display the sum of all counters
  output$total <- renderText({
    total <- counter1_value() + counter2_value() + counter3_value()
    paste("Total:", total)
  })
}

# Run the application
shinyApp(ui = ui, server = server)
