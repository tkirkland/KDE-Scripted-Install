# Google Shell Style Guide Compliance

This project follows the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html).

## Key Requirements

### Naming Conventions
- **Functions**: `snake_case` (e.g., `detect_windows()`)
- **Variables**: `snake_case` (e.g., `target_drive`)
- **Constants**: `UPPERCASE_WITH_UNDERSCORES` (e.g., `VERSION`, `RED`)
- **Files**: `lowercase_with_underscores.sh`

### Formatting Standards
- **Indentation**: 2 spaces (no tabs)
- **Line Length**: 80 characters maximum
- **Control Flow**: `; then` and `; do` on same line
- **Tests**: Use `[[ ]]` instead of `[ ]`
- **Quoting**: Quote all variables consistently

### Function Documentation Template
```bash
#######################################
# Brief description of function purpose.
# Globals:
#   GLOBAL_VAR_1
#   GLOBAL_VAR_2
# Arguments:
#   $1: Description of first argument
#   $2: Description of second argument
# Outputs:
#   Writes progress to stdout
#   Writes errors to stderr
# Returns:
#   0 on success, non-zero on error
#######################################
function_name() {
  local arg1="$1"
  local arg2="$2"
  
  # Function implementation
}
```

### Error Handling Standards
- Always check return values
- Send errors to STDERR using `>&2`
- Use descriptive error messages
- Return appropriate exit codes

### File Organization
```
lib/
├── core.sh           # Core utilities and logging
├── validation.sh     # System validation functions
├── hardware.sh       # Hardware detection
├── network.sh        # Network configuration
├── config.sh         # Configuration management
└── installation.sh   # Installation phases
```

### Enforcement Tools
- `shellcheck` for static analysis
- Custom linting rules for style compliance
- Pre-commit hooks for automated checking

## Modular Architecture Standards

### Module Structure Template
```bash
#!/bin/bash
#
# Module: [MODULE_NAME]
# Purpose: [Brief description]
# Dependencies: [List required modules]

#######################################
# Load dependencies
#######################################
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"

#######################################
# Module constants
#######################################
readonly MODULE_VERSION="1.0"

# Function definitions follow...
```

### Import Standards
```bash
# In main script
readonly LIB_DIR="${SCRIPT_DIR}/lib"
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/validation.sh"
# etc.
```

## Compliance Checklist

### Before Committing
- [ ] All functions have proper documentation headers
- [ ] Line length ≤ 80 characters
- [ ] Consistent 2-space indentation
- [ ] All variables quoted appropriately
- [ ] shellcheck passes with no warnings
- [ ] Error messages go to STDERR
- [ ] Return codes are meaningful

### Module Standards
- [ ] Each module has single responsibility
- [ ] Dependencies clearly documented
- [ ] Functions are testable in isolation
- [ ] No global variable pollution
- [ ] Proper error propagation

---

*Enforced throughout gradual modular refactoring*