let extract ~observation ~parsed =
  Reference_extraction.make ~observation
    ~definitions:parsed.Markdown_inspect.reference_definitions
    ~uses:parsed.Markdown_inspect.reference_uses
