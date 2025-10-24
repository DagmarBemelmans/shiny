# Shiny Module Demo App

This is a simple demonstration of using Shiny modules to create reusable components.

## Features

- **Counter Module**: A reusable counter component with increment, decrement, and reset functionality
- **Multiple Instances**: Three independent counter instances with different initial values
- **Module Communication**: The main app calculates and displays the sum of all counter values

## Running the App

To run this app, make sure you have the `shiny` package installed, then:

```r
# From R console
shiny::runApp("demo_app")

# Or navigate to the demo_app directory and run:
shiny::runApp()
```

## Module Structure

The app consists of two files:

1. **counter_module.R**: Contains the module definition
   - `counterUI()`: Creates the UI for the counter module
   - `counterServer()`: Implements the server logic for the counter module

2. **app.R**: The main application file that uses the module
   - Creates three instances of the counter module
   - Displays the sum of all counter values

## About Modules

Shiny modules are a way to create reusable components in Shiny applications. They help:

- Organize code into logical, self-contained pieces
- Avoid namespace collisions
- Create reusable components that can be shared across apps
- Make complex apps easier to maintain

Each module has a UI function and a server function that work together as an independent unit.
