# Demonstration of Namespace Transformation in Shiny Modules
#
# This file shows exactly what happens to IDs when they pass through
# the namespace mechanism.

# ==============================================================================
# 1. Basic NS() Function Usage
# ==============================================================================

cat("\n=== Basic NS() Usage ===\n")

# Create a namespace function for "counter1"
ns1 <- NS("counter1")

# Apply it to various IDs
cat("ns1('button')     ->", ns1("button"), "\n")
cat("ns1('value')      ->", ns1("value"), "\n")
cat("ns1('increment')  ->", ns1("increment"), "\n")

# Create a namespace function for "counter2"
ns2 <- NS("counter2")

cat("\nns2('button')     ->", ns2("button"), "\n")
cat("ns2('value')      ->", ns2("value"), "\n")

# Notice: Same input IDs, different output IDs!

# ==============================================================================
# 2. How Module Input/Output Works
# ==============================================================================

cat("\n\n=== Inside a Module ===\n")

cat("\nIn your module code, you write:\n")
cat("  input$increment\n")
cat("  output$value\n")

cat("\nBut what actually happens:\n")
cat("  input$increment  -> looks up 'counter1-increment' in the real input\n")
cat("  output$value     -> renders to 'counter1-value' in the real output\n")

# ==============================================================================
# 3. Nested Namespaces
# ==============================================================================

cat("\n\n=== Nested Modules ===\n")

# Parent module namespace
ns_parent <- NS("parent")

# Child module namespace (nested inside parent)
# When makeScope is called from within a module, it compounds the namespace
ns_child <- function(id) {
  ns_parent(NS("child")(id))
}

cat("Parent module transforms 'button' to:", ns_parent("button"), "\n")
cat("Child module (nested) transforms 'button' to:", ns_child("button"), "\n")

# ==============================================================================
# 4. Practical Example: Tracing a Button Click
# ==============================================================================

cat("\n\n=== Tracing a Button Click ===\n")

module_id <- "counter1"
button_id <- "increment"

cat("\n1. In HTML (UI side):\n")
cat("   - You write: actionButton(ns('increment'), ...)\n")
cat("   - HTML gets: <button id='", NS(module_id)(button_id), "'>...</button>\n")

cat("\n2. User clicks the button:\n")
cat("   - Browser sends: { '", NS(module_id)(button_id), "': <click_count> }\n")

cat("\n3. Server receives and stores in real input:\n")
cat("   - input['", NS(module_id)(button_id), "'] = <click_count>\n")

cat("\n4. Inside your module, you access input$increment:\n")
cat("   - Module sees: input$increment\n")
cat("   - Namespace wrapper transforms: 'increment' -> '", NS(module_id)(button_id), "'\n")
cat("   - Retrieves: input['", NS(module_id)(button_id), "']\n")

cat("\n5. It just works! You never see the full namespaced ID in your module code.\n")

# ==============================================================================
# 5. Multiple Instances - Why Namespacing Matters
# ==============================================================================

cat("\n\n=== Why Namespacing Prevents Conflicts ===\n")

# Imagine we have three counter instances
instances <- c("counter1", "counter2", "counter3")

cat("\nThree separate counter modules, each with an 'increment' button:\n")
for (inst in instances) {
  ns <- NS(inst)
  cat("  ", inst, ": button ID becomes '", ns("increment"), "'\n", sep = "")
}

cat("\nWithout namespacing, all three would try to use the same ID 'increment'")
cat(" - CONFLICT!\n")
cat("With namespacing, each gets a unique ID - NO CONFLICT!\n")

# ==============================================================================
# 6. The Session Proxy Mechanism
# ==============================================================================

cat("\n\n=== Session Proxy Pattern ===\n")

cat("\nThe session object you receive in a module is actually a proxy:\n\n")

cat("session$input      -> Namespaced wrapper (counter1-*)\n")
cat("session$output     -> Namespaced wrapper (counter1-*)\n")
cat("session$ns         -> Namespace function\n")
cat("session$userData   -> Falls through to parent (shared across all modules!)\n")
cat("session$clientData -> Falls through to parent (shared across all modules!)\n")

cat("\nThis allows:\n")
cat("  - Isolation: Each module has its own input/output namespace\n")
cat("  - Sharing: All modules can access common session properties\n")

# ==============================================================================
# 7. Return Values and Communication
# ==============================================================================

cat("\n\n=== Module Communication ===\n")

cat("\nModules can return reactive values:\n\n")

cat("counterServer <- function(id) {\n")
cat("  moduleServer(id, function(input, output, session) {\n")
cat("    count <- reactiveVal(0)\n")
cat("    # ... module logic ...\n")
cat("    return(count)  # <-- Return the reactive value\n")
cat("  })\n")
cat("}\n\n")

cat("In the parent app:\n")
cat("counter1_val <- counterServer('counter1')\n")
cat("counter2_val <- counterServer('counter2')\n\n")

cat("Now the parent can react to module values:\n")
cat("total <- reactive({ counter1_val() + counter2_val() })\n")

cat("\nThis creates a communication channel FROM modules TO parent!\n")

# ==============================================================================
# Summary
# ==============================================================================

cat("\n\n" , paste(rep("=", 70), collapse = ""), "\n")
cat("SUMMARY: The Module Namespace Pipeline\n")
cat(paste(rep("=", 70), collapse = ""), "\n\n")

cat("1. NS() creates a function that prepends 'id-' to input strings\n")
cat("2. Module UI uses ns() to transform all element IDs\n")
cat("3. HTML contains the transformed IDs (e.g., 'counter1-button')\n")
cat("4. session$makeScope() creates namespaced input/output wrappers\n")
cat("5. Inside module, input$button is intercepted and transformed\n")
cat("6. The wrapper looks up the real ID 'counter1-button' behind the scenes\n")
cat("7. Module code stays simple: just write 'button', not 'counter1-button'\n")
cat("8. Multiple instances work independently thanks to different namespaces\n\n")

cat("Result: Reusable, composable, conflict-free modules! \n\n")
