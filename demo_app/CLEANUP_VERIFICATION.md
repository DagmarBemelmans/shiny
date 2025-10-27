# How to Verify Module Cleanup

This document explains how to verify that a Shiny module has been completely cleaned up with no lingering observers, pending flushes, or memory leaks.

## The Challenge

After calling `cleanup()` on a module, you want to verify:
- All observers are destroyed
- No pending flushes in the reactive queue
- Outputs are cleaned up
- Memory is freed
- No zombie reactives remain

## Inspection Methods

### Method 1: Check Observer Destroyed State

**Location:** `R/reactives.R:1126`

Every `Observer` has a `.destroyed` field:

```r
Observer <- R6Class('Observer',
  public = list(
    .destroyed = logical(0)
  )
)
```

**How to check:**

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    obs <- observeEvent(input$button, { ... })

    cleanup <- function() {
      cat("Before destroy: .destroyed =", obs$.destroyed, "\n")
      obs$destroy()
      cat("After destroy: .destroyed =", obs$.destroyed, "\n")
    }

    list(
      observer = obs,  # Expose for testing
      cleanup = cleanup
    )
  })
}

# Usage
module_ref <- counterServer("test")
print(module_ref$observer$.destroyed)  # FALSE
module_ref$cleanup()
print(module_ref$observer$.destroyed)  # TRUE
```

**Important:** `.destroyed` is a private field, but R6 allows access. In production, use the pattern below instead.

### Method 2: Check Reactive Environment Flush Queue

**Location:** `R/react.R:190`

The reactive environment tracks pending flushes:

```r
ReactiveEnvironment <- R6Class('ReactiveEnvironment',
  public = list(
    .pendingFlush = 'PriorityQueue',
    hasPendingFlush = function() {
      return(!.pendingFlush$isEmpty())
    }
  )
)
```

**How to check:**

```r
# Access the reactive environment
check_pending_flushes <- function() {
  env <- shiny:::.getReactiveEnvironment()

  if (env$hasPendingFlush()) {
    cat("⚠️  Warning: Pending flushes exist!\n")
    cat("   Some observers are scheduled to execute.\n")
    return(TRUE)
  } else {
    cat("✓ No pending flushes - clean!\n")
    return(FALSE)
  }
}

# Usage
module_ref$cleanup()
Sys.sleep(0.1)  # Allow time for cleanup
check_pending_flushes()
```

**Note:** `:::` accesses internal functions - this is for debugging only!

### Method 3: Check Session Busy Count

**Location:** `R/shiny.R:360`

The session tracks how many observers are executing:

```r
ShinySession <- R6Class('ShinySession',
  private = list(
    busyCount = 0L  # Number of pending observer callbacks
  )
)
```

When `busyCount > 0`, observers are executing.

**How to check:**

```r
check_session_busy <- function(session) {
  # Access private field (internal use only!)
  busy <- session$.__enclos_env__$private$busyCount

  if (busy > 0) {
    cat("⚠️  Warning: Session busy (busyCount =", busy, ")\n")
    cat("   Observers are currently executing.\n")
    return(TRUE)
  } else {
    cat("✓ Session idle (busyCount = 0)\n")
    return(FALSE)
  }
}

# Usage in server function
check_session_busy(session)
```

**Warning:** Accessing private fields is fragile and may break in future versions!

### Method 4: Use Reactlog to Visualize Dependencies

**Location:** `R/graph.R:60`

The reactlog shows all reactive relationships:

```r
# Enable reactlog at app startup
options(shiny.reactlog = TRUE)
# Or use: reactlog::reactlog_enable()

# Run your app and create/cleanup modules

# View the reactlog
reactlogShow()
```

**What to look for:**
- After cleanup, destroyed observers should show as "invalidated" with no subsequent executions
- Check dependency graph - cleaned modules shouldn't have active connections
- Look for timestamp gaps - cleaned observers stop executing

**Programmatic access:**

```r
# Get reactlog data
log_data <- reactlog()

# Inspect structure
str(log_data, max.level = 2)

# Look for your module's observers
# (This requires parsing the log structure)
```

### Method 5: Monitor Output Executions

Track how many times an output executes:

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    execution_count <- 0

    output$value <- renderText({
      execution_count <<- execution_count + 1
      cat(sprintf("[%s] Output executed (count: %d)\n",
                  id, execution_count))
      paste("Value:", execution_count)
    })

    cleanup <- function() {
      output$value <- NULL
      cat(sprintf("[%s] Output cleaned up (total executions: %d)\n",
                  id, execution_count))
    }

    list(
      get_execution_count = function() execution_count,
      cleanup = cleanup
    )
  })
}

# Usage
module_ref <- counterServer("test")

# Trigger some renders...
# ...

cat("Executions before cleanup:", module_ref$get_execution_count(), "\n")
module_ref$cleanup()

# Trigger inputs that would normally cause re-render
# If cleanup worked, execution count shouldn't increase

Sys.sleep(0.5)
cat("Executions after cleanup:", module_ref$get_execution_count(), "\n")
```

### Method 6: Memory Profiling

Use R's memory tools to detect leaks:

```r
# Install packages
# install.packages("pryr")
# install.packages("profmem")

library(pryr)

# Measure memory before
mem_before <- mem_used()
cat("Memory before:", format(mem_before), "\n")

# Create module
module_ref <- counterServer("test")

# Trigger some activity
# ...

# Memory after creation
mem_after_create <- mem_used()
cat("Memory after create:", format(mem_after_create), "\n")
cat("Increase:", format(mem_after_create - mem_before), "\n")

# Cleanup
module_ref$cleanup()
module_ref <- NULL  # Remove reference

# Force garbage collection
gc()

# Memory after cleanup
mem_after_cleanup <- mem_used()
cat("Memory after cleanup:", format(mem_after_cleanup), "\n")
cat("Decrease:", format(mem_after_create - mem_after_cleanup), "\n")

# Check if memory returned to baseline (approximately)
if (abs(mem_after_cleanup - mem_before) < 1e6) {  # Within 1MB
  cat("✓ Memory approximately returned to baseline\n")
} else {
  cat("⚠️  Warning: Memory not fully recovered\n")
  cat("   Potential memory leak!\n")
}
```

**More detailed profiling:**

```r
library(profmem)

# Profile memory allocations
p <- profmem({
  module_ref <- counterServer("test")
  # ... use module ...
  module_ref$cleanup()
  module_ref <- NULL
  gc()
})

print(p)
total(p)
```

### Method 7: Create a Comprehensive Diagnostic Function

Put it all together:

```r
#' Comprehensive Module Cleanup Diagnostics
#'
#' @param module_ref Reference to module (if available)
#' @param session Shiny session object
#' @param verbose Print detailed information
#'
#' @return List with diagnostic results
diagnose_cleanup <- function(module_ref = NULL, session = NULL, verbose = TRUE) {
  results <- list()

  # Check 1: Observer state
  if (!is.null(module_ref) && !is.null(module_ref$observer)) {
    observer <- module_ref$observer
    destroyed <- tryCatch(
      observer$.destroyed,
      error = function(e) NA
    )
    results$observer_destroyed <- destroyed

    if (verbose) {
      if (isTRUE(destroyed)) {
        cat("✓ Observer destroyed\n")
      } else if (isFALSE(destroyed)) {
        cat("⚠️  Observer still active\n")
      } else {
        cat("?  Observer state unknown\n")
      }
    }
  }

  # Check 2: Pending flushes
  tryCatch({
    env <- shiny:::.getReactiveEnvironment()
    has_pending <- env$hasPendingFlush()
    results$has_pending_flushes <- has_pending

    if (verbose) {
      if (has_pending) {
        cat("⚠️  Pending flushes exist\n")
      } else {
        cat("✓ No pending flushes\n")
      }
    }
  }, error = function(e) {
    results$has_pending_flushes <- NA
    if (verbose) cat("?  Could not check pending flushes\n")
  })

  # Check 3: Session busy
  if (!is.null(session)) {
    tryCatch({
      busy <- session$.__enclos_env__$private$busyCount
      results$session_busy <- busy > 0
      results$busy_count <- busy

      if (verbose) {
        if (busy > 0) {
          cat("⚠️  Session busy (count:", busy, ")\n")
        } else {
          cat("✓ Session idle\n")
        }
      }
    }, error = function(e) {
      results$session_busy <- NA
      if (verbose) cat("?  Could not check session busy state\n")
    })
  }

  # Check 4: Memory usage
  results$memory_used <- mem_used()
  if (verbose) {
    cat("ℹ  Memory used:", format(results$memory_used), "\n")
  }

  # Summary
  if (verbose) {
    cat("\n=== SUMMARY ===\n")
    all_checks_passed <- TRUE

    if (isTRUE(results$observer_destroyed)) {
      cat("✓ Observer cleanup: PASS\n")
    } else if (isFALSE(results$observer_destroyed)) {
      cat("✗ Observer cleanup: FAIL\n")
      all_checks_passed <- FALSE
    }

    if (isFALSE(results$has_pending_flushes)) {
      cat("✓ Flush queue: PASS\n")
    } else if (isTRUE(results$has_pending_flushes)) {
      cat("✗ Flush queue: FAIL\n")
      all_checks_passed <- FALSE
    }

    if (isFALSE(results$session_busy)) {
      cat("✓ Session state: PASS\n")
    } else if (isTRUE(results$session_busy)) {
      cat("✗ Session state: FAIL\n")
      all_checks_passed <- FALSE
    }

    if (all_checks_passed) {
      cat("\n🎉 All checks passed - cleanup successful!\n")
    } else {
      cat("\n⚠️  Some checks failed - potential issues\n")
    }
  }

  invisible(results)
}
```

**Usage:**

```r
server <- function(input, output, session) {
  module_ref <- counterServer("test")

  observeEvent(input$cleanup, {
    # Before cleanup
    cat("\n=== BEFORE CLEANUP ===\n")
    before <- diagnose_cleanup(module_ref, session)

    # Cleanup
    module_ref$cleanup()

    # Wait for any pending operations
    Sys.sleep(0.1)

    # After cleanup
    cat("\n=== AFTER CLEANUP ===\n")
    after <- diagnose_cleanup(module_ref, session)

    # Compare
    cat("\n=== COMPARISON ===\n")
    cat("Memory freed:", format(before$memory_used - after$memory_used), "\n")
  })
}
```

## Testing Module Cleanup

Use `testServer()` to verify cleanup in tests:

```r
library(testthat)

test_that("counterServer cleans up properly", {
  # Track state
  observer_state <- list(destroyed = FALSE)

  testServer(counterServer, args = list(id = "test"), {
    # Module is active
    expect_false(observer_state$destroyed)

    # Interact with module
    session$setInputs(increment = 1)
    expect_equal(value(), 1)

    # Store observer reference
    observer_ref <- observer  # If module exposes it

    # Call cleanup
    cleanup()

    # Wait for cleanup
    session$flushReact()

    # Verify observer destroyed
    expect_true(observer_ref$.destroyed)

    # Verify no pending flushes
    env <- shiny:::.getReactiveEnvironment()
    expect_false(env$hasPendingFlush())
  })
})
```

## Automated Cleanup Verification

Create a test helper that runs after every test:

```r
verify_no_leaks <- function() {
  env <- shiny:::.getReactiveEnvironment()

  # Check pending flushes
  if (env$hasPendingFlush()) {
    warning("Test leaked pending flushes!")
  }

  # Force GC and check memory
  gc()

  # Could add more checks here
}

# Use in tests
test_that("module test", {
  # ... test code ...

  # Cleanup
  module_ref$cleanup()

  # Verify
  verify_no_leaks()
})
```

## Interactive Debugging

Run these commands in the R console while your app is running:

```r
# 1. Check reactive environment
env <- shiny:::.getReactiveEnvironment()
env$hasPendingFlush()  # Should be FALSE when idle

# 2. View reactlog
reactlogShow()

# 3. Check memory
pryr::mem_used()

# 4. Force garbage collection
gc()

# 5. Check if session is closed
session$isClosed()  # Should be FALSE while running

# 6. List all reactive IDs (if reactlog enabled)
log <- reactlog()
# Inspect log$log to see all reactive activity
```

## Common Issues and How to Detect Them

### Issue 1: Observer Not Destroyed

**Symptom:**
- Output continues to execute after cleanup
- Execution counter keeps incrementing

**Detection:**
```r
# Observer's .destroyed field is FALSE
observer$.destroyed  # Should be TRUE after cleanup
```

### Issue 2: Circular References

**Symptom:**
- Memory not freed after cleanup
- Objects not garbage collected

**Detection:**
```r
# Memory doesn't decrease after cleanup + gc()
mem_before <- pryr::mem_used()
module_ref$cleanup()
module_ref <- NULL
gc()
mem_after <- pryr::mem_used()
mem_before - mem_after  # Should be > 0
```

### Issue 3: Pending Flushes

**Symptom:**
- Session remains "busy" after cleanup
- Observers scheduled but not executed

**Detection:**
```r
# Check reactive environment
env <- shiny:::.getReactiveEnvironment()
env$hasPendingFlush()  # Should be FALSE
```

### Issue 4: Output Not Cleared

**Symptom:**
- Output still shows in browser
- UI element not empty

**Detection:**
```r
# Check if output is NULL
session$output[[module_id]]  # Should error or be NULL

# Or check the outputs list
names(session$.__enclos_env__$private$.outputs)
# Module outputs shouldn't be in this list
```

## Best Practices for Verifiable Cleanup

### 1. Expose Observer References (for testing)

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    obs <- observeEvent(...)

    cleanup <- function() {
      obs$destroy()
    }

    list(
      cleanup = cleanup,
      .observer = obs  # Prefix with . to indicate "internal"
    )
  })
}

# In tests
module_ref <- counterServer("test")
expect_false(module_ref$.observer$.destroyed)
module_ref$cleanup()
expect_true(module_ref$.observer$.destroyed)
```

### 2. Add Cleanup Verification to Module

```r
counterServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    obs <- observeEvent(...)

    cleanup <- function() {
      obs$destroy()
    }

    verify_cleanup <- function() {
      list(
        observer_destroyed = obs$.destroyed,
        timestamp = Sys.time()
      )
    }

    list(
      cleanup = cleanup,
      verify = verify_cleanup
    )
  })
}

# Usage
module_ref$cleanup()
verification <- module_ref$verify()
stopifnot(verification$observer_destroyed)
```

### 3. Use Lifecycle Hooks

```r
counterServer <- function(id, on_cleanup = NULL) {
  moduleServer(id, function(input, output, session) {
    obs <- observeEvent(...)

    cleanup <- function() {
      message("Cleaning up module: ", id)

      obs$destroy()

      # Call hook
      if (!is.null(on_cleanup)) {
        on_cleanup(id)
      }

      message("Cleanup complete: ", id)
    }

    list(cleanup = cleanup)
  })
}

# Usage
cleanup_log <- list()
module_ref <- counterServer("test", on_cleanup = function(id) {
  cleanup_log[[id]] <<- Sys.time()
})

module_ref$cleanup()
print(cleanup_log)  # Verify hook was called
```

## Summary

**To verify module cleanup:**

1. **Check observer state** - `.destroyed` should be `TRUE`
2. **Check pending flushes** - `hasPendingFlush()` should be `FALSE`
3. **Check session busy** - `busyCount` should be `0`
4. **Use reactlog** - visualize dependencies and execution
5. **Monitor memory** - ensure memory is freed
6. **Test systematically** - use `testServer()` and assertions

**Quick diagnostic:**

```r
# After cleanup
module_ref$cleanup()
Sys.sleep(0.1)

# Check everything
diagnose_cleanup(module_ref, session, verbose = TRUE)
```

**For production:**
- Use cleanup hooks and logging
- Monitor memory usage over time
- Use reactlog in development only
- Write tests that verify cleanup

This ensures your modules are truly cleaned up with no lingering resources!
