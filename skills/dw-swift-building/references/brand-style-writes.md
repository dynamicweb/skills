# Brand style writes: measured MCP shapes

The MCP calls that put a brand kit on a Swift 2 website — files, fonts, typography, button style,
colour schemes, the website's style fields, the favicon, the header and footer logos and row
schemes — with the argument and read shapes measured on one host. Every shape below was a real call
and a read-back [dw 10.30.6 · mcp 0.6.3-BETA]. The replayable form is the `content.design-styles`
recipe of the function ledger.

## Contents

- [Order](#order)
- [Files: list_files, create_folder, upload_file](#files-list_files-create_folder-upload_file)
- [Fonts and typography](#fonts-and-typography)
- [Button style and colour schemes](#button-style-and-colour-schemes)
- [Website wiring and the favicon](#website-wiring-and-the-favicon)
- [Header and footer: slots, logos and row schemes](#header-and-footer-slots-logos-and-row-schemes)
- [Checking the result](#checking-the-result)

## Order

Files first (a font, a logo and a favicon must exist before anything names them), then fonts,
typography, button style and schemes, then `save_areas` points the website at them, then the
favicon, logos and header and footer rows. Read every object back by its id; a save's own answer is
not the evidence.

## Files: list_files, create_folder, upload_file

- `upload_file {path, content, isBase64, overwrite}` writes only under `/Files/Images` and
  `/Files/Files/Integration`, creates missing parent folders, and refuses an existing file unless
  `overwrite: true`. Send every file as base64 with `isBase64: true`; SVG text works the same way.
  `.woff2`, `.svg` and `.png` were accepted. A kit that addresses font files under
  `Templates/Designs/Swift-v2/Custom/fonts` cannot be uploaded there: upload them to an image
  folder and name that path in the font.
- `list_files {path}` answers `{count, data: [{name, path, isDirectory, byteSize}]}`. A folder that
  does not exist is an error result, not an empty list: find a brand folder from its parent
  (`/Files/Images`) and match `name` with `isDirectory: true`. Compare a file by `byteSize`.
- `create_folder {path}` makes the folder (same two roots).

## Fonts and typography

- `save_fonts {fonts: [{id, name, family, filePath, weight, style}]}` overwrites the whole font;
  `get_fonts` answers `{count, data}` with the same members. `weight` is a name (`Regular`, `Bold`).
- `save_typographies {typographies: [{id, name, baseFontSize, baseFontScale, paragraphFont |
  paragraphCustomFontId, paragraphFontStyle, paragraphFontWeight, paragraphLineHeight,
  paragraphLetterSpacing, paragraphTextTransformation, heading…, button…}]}` overwrites the whole
  typography. `get_typographies` leaves out a member that is unset (a style, a custom font id, a family
  name when a custom font is named).
- Enum members take the name (`Regular`, `Uppercase`) or numeric text (`"400"`, `"1"`) and read back
  as names; a JSON number is refused (`must be a string, got the number`). The stored model file and
  a brand kit use the numbers, the tools the names.
- **Send every line height.** An unsent one is stored as 0 and the generated sheet emits
  `--dw-line-height: 0`, which stacks every line of text on top of each other.
- A custom font id makes the generated typography sheet emit an `@font-face` with `font-display: swap`
  and the font's `filePath`. **A typography that mixes a custom font with a hosted family** emits the
  hosted family's `@import` after that `@font-face`, and a browser ignores an `@import` that follows
  other rules: the hosted role falls back to the browser default. Self-host every role's face, or none.

## Button style and colour schemes

- `save_button_styles {buttonStyles: [{id, name, shape, borderSize, paddingX, paddingY}]}`: `shape` is
  `Squared`, `Rounded` or `Pill`; padding is rem. Button colours come from the schemes.
- `save_color_schemes {colorSchemes: [{groupId, groupName, id, name, backgroundColor, foregroundColor,
  primaryButtonColor, secondaryButtonColor}]}` creates the group on the first save; one item per call
  or all seven together. `get_color_schemes` answers one row per scheme with `groupId`. Colours are
  stored in the case they were sent. Keep Swift's seven scheme ids (`light`, `lightgrey1`,
  `lightgrey2`, `dark`, `darksubtle`, `primary`, `secondary`): every row names its scheme by id, so a
  renamed id leaves the row unpainted with no error.

## Website wiring and the favicon

- `get_area_by_id {areaId}` answers the website itself (no `data` wrapper), with `colorSchemeGroupId`,
  `colorSchemeId`, `typographyId`, `buttonStyleId`, `itemType` (`Swift-v2_Master`) and `itemId`.
- `save_areas {areas: [{id, colorSchemeGroupId, colorSchemeId, typographyId, buttonStyleId}]}` changes
  only the members sent. The served head links the new `Styles/ColorSchemes`, `Styles/Buttons` and
  `Styles/Typography` sheets on the next request.
- The favicon is the master item's `Favicon` file field: `set_item_field_values {values: [{itemType:
  "Swift-v2_Master", itemId, fieldSystemName: "Favicon", value: "/Files/Images/<folder>/<file>"}]}`, read
  with `get_item_field_values {itemType, itemId}`. The read shows the new path at once; **the storefront
  keeps linking the old favicon until the host recycles**, and a `save_areas` call does not refresh it.

## Header and footer: slots, logos and row schemes

- The master item's `HeaderDesktop`, `HeaderMobile`, `FooterDesktop` and `FooterMobile` fields hold the
  selected page's id as text; the page tools accept that text as `pageId`.
- The logo is the `Swift-v2_Logo` paragraph on that page (`get_paragraphs_by_page_id`, match
  `itemType`). Its `Image` is a file field: `set_paragraph_item_fields {paragraphId, fields: {Image:
  "/Files/Images/<folder>/logo.svg", LogoName}}` takes the path as text and refuses a file that does not
  exist. An SVG logo is inlined into the header markup.
- A row's scheme is `save_grid_rows {gridRows: [{id, colorSchemeId}]}`; the id is resolved in the
  website's scheme group, so wire the website first.

## Checking the result

`fetch_frontend_page_html {path}` answers a summary with `statusCode` for any served path, a file
included: the generated sheets (`/Files/System/Styles/<kind>/<id>.css`), each font file and the logo
answer 200. No MCP read returns the served head or a computed style; the painted colours, the loaded
font faces and the favicon link are checked in a browser.
