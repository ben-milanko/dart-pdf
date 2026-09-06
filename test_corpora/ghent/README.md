# Ghent PDF Output Suite V5 audit

This directory contains 54 GWG/Ghent test PDFs (57 pages including the three
composite sheets). The audit below records what each patch is testing and the
condition used to judge it. The source documents are self-grading: a clearly
visible filled `X`, a cross, a missing check mark, or an actual object that does
not match its reference is a failure. The GWG guidance explicitly says that a
faint or outlined `X` caused by raster-edge differences is not a failure; the
page must be judged at normal viewing distance.

The renderer passes every entry below. `packages/dart_pdf_editor/test/
ghent_render_test.dart` renders and baseline-compares every page with no
per-document exclusions. Focused, platform-independent tests additionally pin
overprint, indexed JPX, image colorants, 16-bit predictors, ICC transforms,
transparency groups, native luminosity masks, and soft-mask blend ordering.

Official suite and interpretation guidance:

- <https://gwg.org/gos5/>
- <https://gwg.org/wp-content/uploads/2021/05/GWG_PDF_Color_webinar.pdf>

## 1-CMYK

| Test | Intent and passing condition | Result |
| --- | --- | --- |
| GWG010 CMYK OP | CMYK overprint and OPM 0/1 across fonts, vectors, images, image masks, and shadings; each row must exhibit its specified knockout/zero-component behavior. | Pass |
| GWG011 Overprint Mode | OPM 0 replaces zero CMYK components while OPM 1 preserves them; the self-grading markers must have the expected visibility. | Pass |
| GWG050 Font Substitution | Embedded fonts must be used rather than substituted. | Pass |
| GWG051 subset PS names identical | Distinct subsets sharing a PostScript name must not be conflated. | Pass |
| GWG052 subset PS names different | Differently named subsets must select their own embedded programs. | Pass |
| GWG060 Shading | Axial/radial shading functions, domains, and extension behavior must reproduce the reference. | Pass |
| GWG061 Shading | Additional shading/function combinations must reproduce the reference without seams or missing fills. | Pass |
| GWG082 DeviceN Support 4c | Four-component DeviceN images/graphics must resolve all process colorants and show the positive checks. | Pass |
| GWG090 Font Support | The suite's Type 1, TrueType, Type 3, and composite-font samples must render their intended glyphs. | Pass |
| GWG091 OpenType Font Support | Embedded OpenType/CFF font samples must render their intended glyphs. | Pass |
| GWG150 Optional Content OCCD | Optional-content configuration dictionaries must select the intended default state. | Pass |
| GWG151 Optional Content RBGroup | Radio-button optional-content groups must enforce their mutually exclusive state. | Pass |
| GWG152 Optional Content OCMD | Optional-content membership dictionaries and visibility policies must select the intended content. | Pass |
| GWG160 DeviceCMYK transparency, non-knockout | All PDF blend modes in a non-knockout CMYK group must match the reference patches. | Pass |
| GWG161 DeviceCMYK transparency, knockout | Knockout groups must composite each object against the group backdrop, with blend-mode results matching the references. | Pass |
| GWG162 DeviceCMYK transparency, isolated | Isolated groups must ignore the external backdrop for internal blending and match the references. | Pass |
| GWG1610 text soft masks, part 1 | Drop shadow, inner shadow, outer glow, inner glow, and bevel/emboss on text must match the embedded references. | Pass |
| GWG1611 text soft masks, part 2 | Satin, basic feather, directional feather, and gradient feather on text must match the embedded references. | Pass |
| GWG166 image soft masks, DeviceCMYK | The masked image must match the reference and have no solid black contour. | Pass |
| GWG168 vector soft masks, part 1 | Drop shadow, inner shadow, outer glow, inner glow, and bevel/emboss on vectors must match the embedded references. | Pass |
| GWG169 vector soft masks, part 2 | Satin, basic feather, directional feather, and gradient feather on vectors must match the embedded references. | Pass |
| GWG170 JPEG 2000 DeviceCMYK | Indexed JPX/DeviceCMYK pixels must decode to the patch color rather than expose the failure marker. | Pass |
| GWG173 JBIG2 | JBIG2 page/symbol decoding and clipped placement must reproduce the patch; only a faint boundary outline is permissible. | Pass |
| GWG181 16-bit DeviceCMYK | 16-bit samples and predictors must retain the intended CMYK values and hide the failure marker. | Pass |
| GWG190 DeviceN OP Black | Vector and image DeviceN overprint over CMYK black, including zero channels, must produce the four specified flat fields. | Pass |
| GWG191 DeviceN OP Yellow | Vector and image DeviceN overprint over yellow, including zero channels, must produce the four specified flat fields. | Pass |
| GWG192 DeviceN OP White | Vector and image DeviceN overprint over white, including zero channels, must produce the four specified flat fields. | Pass |
| Ghent CMYK composite | Composite pages containing the CMYK tests above must retain the same results when imposed together. | Pass (3 pages) |

## 2-SPOT

| Test | Intent and passing condition | Result |
| --- | --- | --- |
| GWG020 CMYK/spot OP | Both directions of process/spot overprint must flatten all ten font, vector, image, image-mask, and shading markers to spot green. | Pass |
| GWG030 Gray/K/separation black OP | Twelve OPM/background combinations must settle on the specified flat spot green or neutral gray field. | Pass |
| GWG031 gray-image OP | A grayscale image's white samples must preserve the spot backdrop under overprint; no white bounding box may appear. | Pass |
| GWG040 white OP | White overprint/knockout behavior in the PDF/X-1a case must match the page's positive examples. | Pass |
| GWG041 white OP | White overprint/knockout behavior in the PDF/X-3 case must match the page's positive examples. | Pass |
| GWG080 DeviceN Support 6c | Six-color DeviceN indexed images, gradients, and vectors must render all process and spot components and positive checks. | Pass |
| GWG081 DeviceN Support 5c | Five-color DeviceN indexed images, gradients, and vectors must render all process and spot components and positive checks. | Pass |
| GWG120 white OP/KO | White overprint and knockout interactions with transparency/groups must match the intended patches. | Pass |
| Ghent SPOT composite | The imposed spot-color tests above must retain their individual results. | Pass |

## 3-ICC-CMS

| Test | Intent and passing condition | Result |
| --- | --- | --- |
| GWG130 ICC Source Profile | Embedded source profiles and rendering intents must select the correct ICC transforms; no failure marker may remain. | Pass |
| GWG132 ICCBasedCMYK OverPrint | ICCBased CMYK is CIE-based and must not use DeviceCMYK overprint zero-component semantics. | Pass |
| GWG133 ICCBasedRGB OverPrint | ICCBased RGB is CIE-based and must knock out rather than behave like a device-separation space. | Pass |
| GWG161 ICCBasedRGB transparency | ICC RGB colors must enter transparency blending in the output group's blend color space and match the references. | Pass |
| GWG164 ICCBasedCMYK transparency | ICC CMYK colors must enter transparency blending through the output profile and match the references. | Pass |
| GWG167 ICCBasedRGB image soft masks | The ICC image soft mask must match the reference and have no solid black contour. | Pass |
| GWG172 ICCBasedRGB JPEG 2000 | Indexed ICC JPX pixels must decode/color-manage to the comparison patch; only a faint edge outline is permissible. | Pass |
| GWG180 16-bit ICCBasedRGB | 16-bit ICC RGB samples must preserve precision through decoding and profile conversion. | Pass |
| GWG182 16-bit ICCBasedGray | 16-bit ICC gray samples must preserve precision through decoding and profile conversion. | Pass |
| GWG183 16-bit DeviceGray | DeviceGray must be mapped through the output condition's black ramp, consistently with the reference. | Pass |
| GWG184 16-bit ICCBasedCMYK | 16-bit ICC CMYK samples must preserve precision through decoding and profile conversion. | Pass |
| GWG205 ICC v4 CMYK image | ICC v4 CMYK LUT profiles and their interpolation must render the positive image without the failure cross. | Pass |
| GWG206 ICC v4 RGB image | ICC v4 RGB profiles must render the positive image without the failure cross. | Pass |
| GWG220 Color Conversion Indicator | Source-to-output conversion must occur where required and leave the page's conversion indicator in its passing state. | Pass |
| GWG221 OutputIntent Change Indicator | Device colors must use the OutputIntent independently of the current `ri`, while source ICC transforms honor `ri`; the indicator may show only a faint outline. | Pass |
| GWG230 Four different Grays | Equivalent gray definitions and black-point compensation must converge without a visible failure marker. | Pass |
| Ghent ICC-CMS composite | The imposed ICC/color-management tests above must retain their individual results. | Pass (2 pages) |

## Reproducing the audit

From the package directories described in the repository `AGENTS.md`:

```sh
cd packages/pdf_graphics
fvm dart test test/ghent_corpus_test.dart

cd ../dart_pdf_editor
fvm flutter test test/ghent_render_test.dart
```

To inspect every rendered page in one gallery, set `GHENT_RENDER_OUT` as
described at the top of `ghent_render_test.dart`.
