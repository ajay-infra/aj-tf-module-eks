config {
  format = "compact"
}

# Unused declarations: disabled — modules declare locals for readability
# and future use; tflint cannot track all usage paths through expressions.
rule "terraform_unused_declarations" {
  enabled = false
}
