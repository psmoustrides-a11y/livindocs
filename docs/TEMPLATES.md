# Template Customization

livindocs uses Handlebars-style templates as structural guides for document generation. Templates define the section layout and livindocs markers — Claude fills in the content based on codebase analysis.

## How Templates Work

Templates are **not** rendered mechanically. They serve as blueprints that tell the writer agents:
- What sections to include and in what order
- Where to place `<!-- livindocs:start/end -->` markers
- What Handlebars variables represent (project name, entry points, etc.)

The writer agent reads the template, understands the intended structure, and generates content that follows the layout while adapting to the specific project.

## Built-in Templates

| Template | Output | Description |
|---|---|---|
| `readme.md.hbs` | `README.md` | Project README with overview, features, setup, API summary |
| `architecture.md.hbs` | `docs/ARCHITECTURE.md` | Architecture doc with Mermaid diagrams |
| `onboarding.md.hbs` | `docs/ONBOARDING.md` | New developer onboarding guide |
| `adr.md.hbs` | `docs/decisions/ADR-N.md` | Architecture Decision Record |

## Custom Templates

To customize the structure of generated docs:

1. Create a templates directory in your project:
   ```bash
   mkdir -p .livindocs/templates
   ```

2. Copy and modify a built-in template:
   ```bash
   cp <plugin-dir>/templates/readme.md.hbs .livindocs/templates/readme.md.hbs
   ```

3. Configure livindocs to use your templates:
   ```yaml
   # .livindocs.yml
   templates_dir: .livindocs/templates/
   ```

## Template Variables

Templates use Handlebars syntax. Available variables:

### Global
- `{{project.name}}` — Project name from config
- `{{project.description}}` — Project description
- `{{license}}` — License type

### README
- `{{entryPoint}}` — Main entry point file path
- `{{packageFile}}` — Package manager file (package.json, go.mod, etc.)
- `{{installCommand}}` — Install command for the project
- `{{runCommand}}` — Run/start command
- `{{prerequisites}}` — Array of prerequisites

### Architecture
- `{{modules}}` — Array of modules with `id`, `name`, `path`
- `{{entryPoints}}` — Array with `path` and `description`
- `{{runtimeDeps}}` — Runtime dependencies with `name`, `version`, `purpose`
- `{{devDeps}}` — Dev dependencies

### ADR
- `{{number}}` — ADR number
- `{{title}}` — Decision title
- `{{date}}` — Decision date
- `{{status}}` — accepted/deprecated/superseded
- `{{authors}}` — Array of author names
- `{{relatedCommits}}` — Array with `hash` and `subject`
- `{{relatedPRs}}` — Array with `number` and `title`

## Section Markers

Every content section must be wrapped in markers:

```markdown
<!-- livindocs:start:section-name -->
Content goes here...
<!-- livindocs:refs:path/to/source.ts:10-50 -->
<!-- livindocs:end:section-name -->
```

When customizing templates, keep the marker pattern. The section name must be unique within the document. The `refs` anchor links the section to source files for staleness tracking.

## Adding New Sections

To add a section that doesn't exist in the built-in template, add a new marker block:

```markdown
<!-- livindocs:start:my-custom-section -->
## My Custom Section

{{! Instructions for Claude: describe what this section should contain }}

<!-- livindocs:end:my-custom-section -->
```

The `{{! comment }}` syntax provides instructions to the writer agent about what content to generate for this section.

## Removing Sections

Delete the entire marker block (start through end) from your custom template. The writer agent will skip sections not present in the template.

## Tips

- Keep section names kebab-case: `arch-overview`, not `Architecture Overview`
- Use `{{! comments }}` liberally to guide content generation
- The template doesn't need to be valid Markdown — it's a guide, not a literal render
- Custom templates are version-controlled with your project, so team members share the same doc structure
