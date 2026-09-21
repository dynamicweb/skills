# The paragraph-as-endpoint pattern

A Swift 2 paragraph can serve a non-page payload — JSON, CSV, a parsed upload, a file — with **no
custom C#, no new package and no deploy**. That makes it the reachable shape on a solution where
controllers are discouraged or a change window has a restart budget of zero. It also has a response
contract that is narrower than `IResponse` looks, and most of this file is that contract.

Surfaces used below: the **template surface** (`.cshtml` under `Files/Templates/`) and **MCP tools**
in `snake_case` for the content rows the recipe needs. Those two are the whole surface this recipe
uses.

## Contents

- [1. Build the endpoint — ordered recipe](#1-build-the-endpoint--ordered-recipe)
- [2. The response contract — what reaches the wire](#2-the-response-contract--what-reaches-the-wire)
- [3. Delivering a non-HTML payload](#3-delivering-a-non-html-payload)
- [4. Libraries already in bin](#4-libraries-already-in-bin)
- [5. Refusing a request properly](#5-refusing-a-request-properly)

## 1. Build the endpoint — ordered recipe

1. **Put the paragraph on a service page and address it by id.** The shipped
   `Swift-v2_PageClean.cshtml` layout renders exactly one paragraph and nothing else when
   `?ParagraphID=` is supplied, which strips the grid-section wrapper a normal page puts around
   paragraph output.

   ```
   GET /Default.aspx?ID=<pageId>&ParagraphID=<paragraphId>&ids=A,B,C
   ```

   *Assert:* the same URL without `ParagraphID` returns the identical body wrapped in
   `<section data-swift-gridrow>`; with it, the body stands alone.

2. **Take the paragraph out of the page's own composition.** A service page that already hosts one
   endpoint with a measured contract changes what that endpoint returns the moment a second
   paragraph is added — the friendly URL renders every active row, so the second body, and even its
   empty grid-row wrapper, is appended to the first one's document. Setting the paragraph's grid row
   `GridRowActive = 0` (MCP `save_grid_rows`, plus the row's language mirror) removes it from the
   page while leaving it **fully addressable by `?ParagraphID=`**. "Inactive" reads as "will not
   render"; when addressed directly, it does.

   *Assert:* the host page's anonymous friendly URL returns its original body byte for byte, and
   `POST /Default.aspx?ID=<pageId>&ParagraphID=<paragraphId>` still answers.

3. **Render nothing unless the parameter you are addressed with is present at all** — `null`, not
   empty. An endpoint that keys off an empty-string test still emits its wrapper on every request
   the page serves for other reasons.

4. **Resolve the endpoint's own address by item type, not by navigation tag.** A template that has
   just created its service page cannot find it through `GetPageIdByNavigationTag()`:
   `PageNavigationTag` is not on the MCP `save_pages` model, and writing it another way does not
   make the lookup work.

   ```cshtml
   @{
       var endpoints = Services.Paragraphs.GetParagraphsByAreaID(areaId);
       // then pick the one whose item type is the endpoint's
   }
   ```

   The paragraph cache is invalidated by the API write that created the paragraph, so the item-type
   lookup is cache-fresh on the very next request.

   Writing the tag is not the alternative: the column write does not refresh the page cache, so
   `GetPageIdByNavigationTag()` keeps returning `0` until the host restarts. The item-type lookup
   owes nothing. Outside the product: see dw-data-access `recipes-content.md`
   §Writing `PageNavigationTag` directly.

5. **Read the request body from the template.** `Dynamicweb.Context.Current.Request.Form["<key>"]`
   is readable from a Razor paragraph, so a POST body reaches the endpoint with nothing depending on
   a multipart or request-file API. Binary payloads travel as base64 in an ordinary form field.

6. **Write the template path fully qualified** —
   `Designs/<design>/Paragraph/<ItemType>/<ItemType>.cshtml`. A relative `ParagraphTemplate`
   resolves against `/Files/Templates/` and its miss is an HTTP 200 with English prose in the
   layout; see [`template-compilation.md`](template-compilation.md) §5.

7. **Emit the payload with `@value`.** Razor writes `@string` unescaped, so a paragraph template
   can emit raw JSON directly.

## 2. The response contract — what reaches the wire

Measured from a Razor paragraph on DW 10.28.x, Swift 2.2, in-process IIS host:

| Member | Reaches the wire? | What actually happens |
|---|---|---|
| `Response.StatusCode` | **Yes** | The client really sees `401`, `403`, `404`. The one response property an endpoint paragraph can rely on |
| `Response.AddHeader(name, value)` | **Yes** | Writes into the header collection, which survives. `Content-Disposition: attachment; filename="…"` set from a paragraph does arrive |
| `Response.ContentType` | **No** | Settable, silent, inert. The page pipeline stamps `text/html` over it *after* the paragraph runs. A shipped JSON endpoint that sets `application/json` serves `Content-Type: text/html` on the wire |
| `Response.BinaryWrite(byte[])` | **No** | Implemented over `Stream.Write`; ASP.NET Core disallows synchronous IO, so it throws `Synchronous operations are disallowed`. `IResponse` exposes no async member to move to |
| `Response.Clear()` | **No effect** | Razor writes to a template writer, not the response buffer, so by the time the paragraph runs there is nothing buffered to clear |

Two consequences worth stating plainly:

- **The `ContentType` failure is invisible in the working case.** A JSON endpoint whose consumer
  reads the body as text and parses it itself works indefinitely while advertising `text/html`.
  Only the next consumer — `fetch().json()`, an XHR with a `responseType`, a browser deciding
  whether to download — discovers it. **Verify the media type on the wire, not in the template
  source**; a `Response.ContentType` line in a shipped file is an intent, not a measurement.
- **The body carries the layout's prelude.** On Swift's clean layout with the endpoint in an
  inactive grid row that is exactly three bytes, `0x20 0x0A 0x0A`. Invisible for HTML and JSON; for
  CSV it is a blank first row that some spreadsheet importers turn into an empty header.
  `Response.Clear()` does not remove it.

## 3. Delivering a non-HTML payload

Given the contract above, two shapes work and one does not:

| Shape | Use it for | Notes |
|---|---|---|
| **`Content-Disposition: attachment` via `AddHeader`** plus the payload as the body | Text payloads where the media type does not have to be right | The filename really arrives; the media type still says `text/html`, and the 3-byte prelude still leads the body |
| **Base64 `data:` URI** on an `<a download="…">` inside the authorised HTML response | Binary payloads, and anything that must land on disk byte-exact | The bytes stay out of every served root, the delivered file is byte-exact and correctly named |
| ~~`BinaryWrite`~~ | — | Throws under the in-process IIS host: it is built on a synchronous `Stream.Write`, which ASP.NET Core disallows. The host option that would relax that is outside the product and outside `Files/` — see dw-setup-config §Host Request-Pipeline Options — so treat `BinaryWrite` as unavailable and use the `data:` URI row above |

**Serving personal data from `/Files` is not the fallback:** `/Files` is served anonymously, so a
document placed there is readable without a session. Keep the bytes outside every served root and
inline them into the authorised response.

## 4. Libraries already in bin

The Razor compilation set references the site `bin`, so **any assembly already deployed there is
callable from a template** with a plain `@using` and a direct `new` — no csproj change, therefore
no `deps.json` change, therefore nothing for a deploy gate that diffs `deps.json` to see.

This is the single most common reason a small feature gets deferred behind a deploy. On a Swift 2 /
DW 10.28.x Suite bin, the parsing libraries present are:

| Library | Type to probe | Use |
|---|---|---|
| EPPlus | `OfficeOpenXml.ExcelPackage` | Read and write `.xlsx`; no `LicenseContext` exception when constructed in-template |
| MiniExcel | `MiniExcelLibs.MiniExcel` | Streaming spreadsheet read |
| CsvHelper | `CsvHelper.CsvReader` | CSV parse |

**No PDF renderer ships in bin** — that case does need a package and a deploy.

Probe before building on it, in the template itself:

```cshtml
@{
    var t = Type.GetType("OfficeOpenXml.ExcelPackage, EPPlus");   // resolves -> the assembly is there
}
```

A reflection probe only proves the assembly loads. Compile one direct `new` into the template as
well — that is what proves the *compilation set* references bin.

## 5. Refusing a request properly

`Response.StatusCode` reaching the wire is what lets an endpoint paragraph refuse honestly instead
of returning `200` with an apology in it: `401` for anonymous, `403` for a caller asking for
another account's document, `403` for an unknown id. Pair each refusal with a marker attribute in
the body so a gate can assert the reason, and log allowed and refused attempts alike.

**This is a real server-side rule only because the paragraph itself performs the work.** When a
Dynamicweb *app* handles the request, it has already done so before any template runs, and a
template-rendered refusal is a UI affordance — see [`template-compilation.md`](template-compilation.md)
§6 for the distinction and the one-line test that tells them apart.

## Cross-references

- [`template-compilation.md`](template-compilation.md) — template resolution, `@Include` scope, and
  render order.
- [dw-content-modelling](../../dw-content-modelling/SKILL.md) — pages, grid rows, paragraphs and the
  MCP tools that create them.
- A payload whose real consumer is a decoupled frontend belongs on the `/dwapi/` delivery API
  rather than on a paragraph. That is out-of-product work — building and hosting the frontend — and
  is not a step this skill can take; `dw-headless-delivery` carries it.
- [dw-extend-csharp-api](../../dw-extend-csharp-api/SKILL.md) — when the work genuinely needs
  compiled code.
