; extends

; Nomad: template { data = <<EOF ... EOF } is consul-template (Go text/template)
(block
  (identifier) @_block
  (#eq? @_block "template")
  (body
    (attribute
      (identifier) @_attr
      (#eq? @_attr "data")
      (expression
        (template_expr
          (heredoc_template
            (template_literal) @injection.content)))))
  (#set! injection.language "gotmpl")
  (#set! injection.combined))
