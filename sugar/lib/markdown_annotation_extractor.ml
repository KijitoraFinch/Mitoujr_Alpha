let extract ~observation ~parsed =
  Annotation_extraction.make ~observation
    ~occurrences:parsed.Markdown_inspect.annotation_occurrences
