# Prior art

Research date: 2026-10-29. Every fact has a source URL. Facts that I could not confirm from a primary source are marked **unverified**. Counts from live APIs are snapshots of that day. The unauthenticated GitHub API rate limit blocked some lookups, so a few repository facts come from raw files, crates.io or search listings.

## 1. Parametric tasks with computer-checked answers

### WeBWorK (PG language, Open Problem Library)

- Current version: PG 2.21 and WeBWorK 2.21, both released 2026-08-05 ([PG releases](https://github.com/openwebwork/pg/releases), [webwork2 releases](https://github.com/openwebwork/webwork2/releases)).
- Task representation: one `.pg` Perl file per problem. Metadata sits in header comments (`DBsubject`, `DBchapter`, `DBsection`, `KEYWORDS`, `Author`, `Institution`). Random values are plain Perl, answers are MathObjects (`Compute("(x-$h)^2-$k")`, `Formula(...)`), and the statement is PGML text with answer blanks such as `[_]{$expandedform}` ([sample problem](https://github.com/openwebwork/pg/blob/main/tutorial/sample-problems/Algebra/ExpandedPolynomial.pg)).
- Answer checking: a `Formula` is compared with the student's formula by evaluating both at random test points. Defaults in the source: 5 points (`num_points`), relative tolerance 1E-4, optional per-variable `limits` ([Formula.pm](https://github.com/openwebwork/pg/blob/main/lib/Value/Formula.pm)). Contexts restrict the allowed answer form: `LimitedPolynomial-Strict` rejects `(5+3)x` and demands `8x` ([sample problem](https://github.com/openwebwork/pg/blob/main/tutorial/sample-problems/Algebra/ExpandedPolynomial.pg)).
- Code license: PG and webwork2 are GPL v2 or later, or Artistic License 1.0, at your choice ([PG LICENSE](https://github.com/openwebwork/pg/blob/main/LICENSE), [webwork2 LICENSE](https://github.com/openwebwork/webwork2/blob/main/LICENSE)). The standalone renderer is GPL-3.0, last push 2025-08-05 ([renderer](https://github.com/openwebwork/renderer)).
- Content license: contributions are CC BY-NC-SA 3.0 unless the author states another open license. Authors keep their copyright ([OPL_LICENSE](https://github.com/openwebwork/webwork-open-problem-library/blob/main/OPL_LICENSE)).
- Size: openwebwork.org claims "over 35,000" problems ([openwebwork.org](https://openwebwork.org/)); the PG README says "over 30,000". The repository tree lists at least 43,140 `.pg` files (Contrib 29,624, OpenProblemLibrary 13,516). The API response was truncated, so that is a lower bound, and it includes near-duplicates ([tree API](https://api.github.com/repos/openwebwork/webwork-open-problem-library/git/trees/main?recursive=1)). Level: lower-division undergraduate math and some advanced courses ([PG README](https://github.com/openwebwork/pg/blob/main/README.md)).
- Curation flow: Contrib (original authors keep control), Pending (editorial board review), OpenProblemLibrary (browsable by subject, chapter, section) ([OPL README](https://github.com/openwebwork/webwork-open-problem-library/blob/main/README.md)).
- Exchange: `.pg` files plus a render service; no standard question interchange format. **Unverified:** export to Moodle XML or QTI.

### STACK (Moodle plus Maxima)

- Current version: plugin 4.14.0 for Moodle 4.2+, version 2026101500 ([version.php](https://github.com/maths/moodle-qtype_stack/blob/master/version.php)). Code license GPL-3.0 ([COPYING.txt](https://github.com/maths/moodle-qtype_stack/blob/master/COPYING.txt)). Maxima is released under the GPL, version not stated ([maxima.sourceforge.io](https://maxima.sourceforge.io/)).
- Task representation: a Moodle XML question of type `stack`. Question variables are Maxima code with random functions. Each student gets a variant from an integer seed; the seed is stored with the attempt ([Deploying](https://github.com/maths/moodle-qtype_stack/blob/master/doc/en/STACK_question_admin/Deploying.md)).
- Variant control: two variants count as the same only if their teacher-written "question note" is identical. Authors are told to pre-generate, test and "deploy" variants. On deployment STACK runs all stored question tests on every variant and stops if one fails ([Deploying](https://github.com/maths/moodle-qtype_stack/blob/master/doc/en/STACK_question_admin/Deploying.md)).
- Answer checking: potential response trees. Each node runs an answer test `[Errors, Result, FeedBack, Note] = AnswerTest(StudentAnswer, TeacherAnswer, [Opt], [Raw])`; `Result` is true, false or fail and selects the branch ([Answer tests](https://docs.stack-assessment.org/en/Authoring/Answer_Tests/)). The docs list 40 tests in 8 groups: equivalence (`AlgEquiv`, `SubstEquiv`, `CasEqual`, `SameType`, `SysEquiv`), syntactic form (`FacForm`, `PartFrac`, `SingleFrac`, `CompSquare`, `Expanded`, `LowestTerms`), rules-based (`EqualComAss`), numerical (`NumRelative`, `NumAbsolute`, `NumSigFigs`, `NumDecPlaces`), units, calculus (`Diff`, `Int`, `Antidiff`), string match (`String`, `Levenshtein`, `SRegExp`), and sets and logic ([Answer tests](https://docs.stack-assessment.org/en/Authoring/Answer_Tests/)). Equivalence is symbolic, by Maxima.
- Content: the repository ships a sample library under CC BY-SA 4.0 ([COPYING.txt](https://github.com/maths/moodle-qtype_stack/blob/master/samplequestions/COPYING.txt)). It holds about 4,086 XML files in nine folders (Algebra-Refresher, Calculus-Refresher, HELM, Introductory-Mathematics, Syntax_practice, Templates and others), so the count of distinct questions is smaller ([tree API](https://api.github.com/repos/maths/moodle-qtype_stack/git/trees/master?recursive=1)). German university pools are covered in section 2.
- Exchange: Moodle XML for import and export. A standalone, stateless REST API has routes `/render`, `/grade`, `/validate`, `/download`, `/test` and `/diff` (the last returns a YAML diff against API defaults). It ships as Docker images and needs a Maxima service ([api/README](https://github.com/maths/moodle-qtype_stack/blob/master/api/README.md)). `moodle-qbank_gitsync` stores one Moodle XML file per question in a git repository ([gitsync README](https://github.com/maths/moodle-qbank_gitsync)).

### Numbas

- Current version: runtime v11.0 (2026-10-01), editor v10.0 (2026-06-23), both Apache-2.0 ([Numbas](https://github.com/numbas/Numbas), [editor](https://github.com/numbas/editor), [licensing](https://github.com/numbas/editor/blob/master/docs/licensing.rst)). Copyright of content stays with its author ([licensing](https://github.com/numbas/editor/blob/master/docs/licensing.rst)).
- Task representation: a JSON exam or question file with a published JSON Schema (`exam_schema.10.0.json`) ([schema folder](https://github.com/numbas/Numbas/tree/master/schema)). Variables are JME expressions (Numbas's own math expression language) and are regenerated for each attempt ([question reference](https://docs.numbas.org.uk/en/latest/question/reference.html)). The runtime uses `seedrandom.js` ([licensing](https://github.com/numbas/editor/blob/master/docs/licensing.rst)).
- Answer checking: a "mathematical expression" part compares two expressions by evaluating them at random points. Defaults in the source: 5 points drawn from [0, 1], checking type `absdiff`, accuracy 0.0001 ([jme.js](https://github.com/numbas/Numbas/blob/master/runtime/scripts/jme.js)). The marking logic itself is written as JME scripts in the repository (`marking_scripts/jme.jme`, `numberentry.jme`, `patternmatch.jme`, and others), so authors can swap marking algorithms ([marking_scripts](https://github.com/numbas/Numbas/tree/master/marking_scripts)).
- Content: the project says "thousands" of tests and questions in its public database are shared under Creative Commons licenses; no count is given ([numbas.org.uk](https://www.numbas.org.uk/)). The editor host `numbas.mathcentre.ac.uk` refused connections on 2026-10-29, so I could not check the license mix or size. **Unverified:** the size and the per-item licenses.
- Exchange: SCORM 2004 and an LTI provider ([numbas.org.uk](https://www.numbas.org.uk/)). A QTI converter exists but handles only multiple choice from QTI 2.1 (Blackboard) and QTI 1.2 (Canvas) ([qti-to-numbas](https://github.com/numbas/qti-to-numbas)).

### PrairieLearn

- Task representation: a directory per question with `info.json` (uuid, title, topic, tags, `gradingMethod`, `singleVariant`), `question.html` built from `pl-*` elements, and `server.py`, which generates random parameters and the matching correct answers ([question overview](https://docs.prairielearn.com/question/overview/), [server.py](https://docs.prairielearn.com/question/server/)). The element index lists about 50 `pl-*` elements ([elements](https://docs.prairielearn.com/elements/)).
- Answer checking: per-element graders. `pl-symbolic-input` takes a variable list and compares with SymPy's equality checker ([pl-symbolic-input](https://docs.prairielearn.com/elements/pl-symbolic-input/)). `gradingMethod` can be `Internal`, `External` (a grader container for code) or `Manual` ([question overview](https://docs.prairielearn.com/question/overview/)).
- License: the Community Edition is AGPL-3.0. Portions copyright UIUC and outside contributors are MIT. Code under `apps/prairielearn/src/ee/` is proprietary Enterprise Edition ([LICENSE](https://github.com/PrairieLearn/PrairieLearn/blob/master/LICENSE)).
- Content and exchange: no central open question library found; the repository carries an example course. Questions are plain files in git, with no interchange standard. **Unverified:** whether third-party course repositories carry open licenses.

### Comparison

| | WeBWorK | STACK | Numbas | PrairieLearn |
|---|---|---|---|---|
| Task language | Perl (PG) | Maxima | JME (JSON container) | Python plus HTML elements |
| Randomness | seeded Perl | integer seed, deployed variants | seed per attempt | per-variant seed |
| Equivalence check | random points, 1E-4 | CAS (Maxima), 40 tests | random points, 1E-4 | SymPy |
| Form checks ("factored", "lowest terms") | contexts | answer tests | pattern match part | custom code |
| Code license | GPL-2+ or Artistic | GPL-3.0 | Apache-2.0 | AGPL-3.0 (plus MIT, EE) |
| Open content | OPL, CC BY-NC-SA 3.0, 30k+ | sample library, CC BY-SA 4.0 | CC items, size unverified | none central |
| Runs without an LMS | yes (own server, renderer) | yes (REST API, needs Maxima) | yes (static HTML) | needs its server |

**What it means for us:** differentiate on the task format and reuse the checking ideas. Not one of the four lets a student assemble a worksheet through an AI client, and all four assume authors who write code (Perl, Maxima, JME, Python). Reuse: the "deploy a vetted seed list and run stored tests on every variant" workflow from STACK; random-point equivalence (WeBWorK and Numbas agree on 5 points and 1E-4); named form checks from STACK; the Contrib, Pending, Library staging from OPL. Ignore as a base: WeBWorK and PrairieLearn code (copyleft, runs author code on the server), and the OPL as bundled content (NC).

## 2. Openly licensed German school content

### Serlo

- License: CC BY-SA 4.0 for the learning material. Attribution: "Quelle: serlo.org" with a link, "Lizenz: CC BY-SA 4.0" with a link, and a note on changes ([Serlo license page](https://de.serlo.org/license/detail/1)). Serlo's code repositories are Apache-2.0 ([api.serlo.org](https://github.com/serlo/api.serlo.org), [frontend](https://github.com/serlo/frontend)).
- API: public GraphQL at `https://api.serlo.org/graphql`, no key needed. The Metadata API returns AMB-conformant JSON-LD through `metadata.resources(first, after, instance, modifiedAfter)` with cursor paging and at most 1000 records per page ([Metadata API wiki](https://github.com/serlo/documentation/wiki/Metadata-API), [Serlo metadata page](https://de.serlo.org/metadata)).
- Size, counted on 2026-10-29 with 9 requests: 8,492 German resources, of which 6,136 are typed `Quiz` (single exercises and exercise groups), 1,692 articles, 285 courses, 280 videos, 99 web apps. All are CC BY-SA 4.0 except 13 under CC BY 4.0 ([live query](https://api.serlo.org/graphql)). Serlo's own page says "4000+ Exercises" ([Serlo metadata page](https://de.serlo.org/metadata)), which looks out of date.
- Structure: the metadata record has no task text. The task itself comes from `uuid(id)`, which returns editor state JSON with an `exercise` plugin: `content`, an optional `interactive` part, and a `solution` with `strategy` and `steps` ([live query, e.g. id 2217](https://api.serlo.org/graphql)). In a random sample of 40 records (19 exercises, 21 groups, drawn from the first 1000), I found 133 exercise nodes: 74 with no interactive part (open tasks), 56 `inputExercise`, 3 `scMcExercise`. Input types: `input-number-exact-match-challenge` 28, `input-string-normalized-match-challenge` 17, `input-expression-equal-match-challenge` 11. All tasks are static: no parameters.
- Practicalities: a Python `urllib` request with its default user agent got HTTP 403, while `curl` worked. I did not work around it. Use an honest, identifying user agent and ask Serlo e.V. about rate limits before a full crawl. **Unverified:** Serlo's terms for bulk use.

### Other German sources

| Source | License | Structured tasks? | API or bulk | Verdict |
|---|---|---|---|---|
| ZUM-Unterrichten | CC BY-SA 4.0 in the page footer; per-page exceptions possible, **unverified** ([sample page](https://unterrichten.zum.de/wiki/Mathematik)) | No: free wikitext with embedded apps. 14,260 pages, 3,480 articles ([MediaWiki API](https://unterrichten.zum.de/api.php?action=query&meta=siteinfo&siprop=statistics&format=json)) | MediaWiki API, open | Later, via the approval queue and LLM extraction |
| TH Köln Aufgabenpool Mathematik | CC BY-SA 4.0 DE ([pool site](https://aufgabenpool.th-koeln.de/)); shop code CC0 ([repo](https://github.com/aufgabenpool/aufgabenpool)) | Yes: STACK tasks for Moodle and ILIAS, university level. Count not stated | Export in the shop; bulk access **unverified**, ask the authors | Best open parametric German pool |
| STACK.nrw | **Unverified** (license not stated) | Yes: consolidates DOMAIN and the TH Köln pool; Git-based sharing system and a pre-beta frontend (ATLAS) in development; runs 2024-06-01 to 2027-12-31 ([stack.nrw](https://stack.nrw/de/)) | none yet | Watch, contact; possible partner |
| WirLernenOnline (WLO) | per item: first 100 hits for "*" show CC BY-SA, CC BY-NC-SA, CC BY-NC-ND, CC BY, "copyright free", custom, and no key on about half ([live query](https://redaktion.openeduhub.net/edu-sharing/rest/search/v1/queries/-home-/mds_oeh/ngsearch)) | No: a meta-catalog of links and files. 318,911 records, 7,632 for "Mathematik Aufgaben" | edu-sharing REST, anonymous, version 11.0 ([_about](https://redaktion.openeduhub.net/edu-sharing/rest/_about)) | Discovery only; bulk import is not realistic |
| MUNDO | **Unverified**; described as license-checked ([OERinfo](https://open-educational-resources.de/materialien/oer-bei-mundo/)) | No: media library of the Länder, partly curated from other OER providers | No public API found; the site renders client-side only | Ignore |
| IQB Abitur tasks, Mathematik | **Unverified**: the page states no license and says publication needs the right holders' consent ([IQB](https://www.iqb.hu-berlin.de/de/schule/sekundarstufe-ii/abituraufgabenpools/)) | PDF files, 624 math tasks, 2017 to 2026 ([IQB list](https://www.iqb.hu-berlin.de/de/schule/aufgaben/sekii/abiturpruefungsaufgaben-mathematik/)) | none | Test corpus for docling, not for import |
| GeoGebra | website content CC BY-NC-SA 4.0, commercial use needs a license ([ToS](https://www.geogebra.org/tos)) | interactive applets | n/a | Avoid |

### Outside Germany

| Source | License | Notes |
|---|---|---|
| Oak National Academy (England) | Open Government Licence v3.0 for curriculum data, MIT for code ([LICENCE-DATA.md](https://github.com/oaknational/oak-open-curriculum-ecosystem/blob/main/LICENCE-DATA.md)) | Open API with lessons, units, quizzes; public-beta MCP server (section 4). English only |
| Illustrative Mathematics K-12 | v.2019-2021 CC BY 4.0; v.360 (2024) CC BY-NC 4.0 ([IM](https://illustrativemathematics.org/site-ip-content/)) | US curriculum text and tasks, English only, static |
| OpenStax | moved from a mix of CC BY and CC BY-NC-SA to CC BY-NC-SA across the library ([OpenStax blog](https://openstax.org/blog/openstax-licensing)) | NC: do not bundle |

**What it means for us:** reuse Serlo first. It is the only large, school-level, openly licensed source with machine-readable tasks, solution steps and a documented API. Pick CC BY-SA 4.0 as the license of the shared bank so Serlo, the STACK library and the TH Köln pool can all flow in; the ShareAlike chain then holds. Keep NC sources (OPL, OpenStax 2026, GeoGebra, IM v.360) out of the bundled bank. Differentiate: we found no open, parametric, school-level (Grundschule to Abitur) task pool in German. Parametric open content is university level (STACK pools, OPL); Serlo is school level but static. WLO and MUNDO are discovery layers, not sources to import.

## 3. Exchange formats

| Format | Carries | Parameters | Answer checking | Complexity | Role for us |
|---|---|---|---|---|---|
| QTI 3.0 (1EdTech) | items, tests, results, MathML | `qti-template-declaration` and `qti-template-processing`, `qti-random-integer` | built-in operators (`qti-equal-rounded`, `qti-math-operator`); `qti-custom-operator` for engines, and the spec's own example uses Maxima | high: large XSD set, packaging, conformance program | export target later, not internal format |
| Moodle XML | question banks; types multichoice, truefalse, shortanswer, matching, cloze, essay, numerical, description | none in core types; plugin types (STACK, calculated, formulas) add their own elements | per type | medium: HTML in CDATA, parser assumes well-formed input and reports no errors | import STACK content; export simple types |
| Moodle calculated | numeric questions with `{x}` wildcards | datasets, at most 100 items, uniform or loguniform | formula plus tolerance (nominal, relative, geometric); no `x^3` (use `pow(x,3)`), no implicit multiplication | low | ignore: too weak for school math |
| GIFT | plain-text quizzes: multiple choice, true/false, short answer, matching, missing word, numerical, essay | none | numerical ranges, e.g. `{#3:2}` accepts 1 to 5 | low | import legacy simple items only |
| H5P | `.h5p` zip: `h5p.json`, `content.json`, `library.json`, `semantics.json` | none found | per content type | medium: runtime libraries travel with the package | optional export of static items |

Sources:

- QTI 3.0 final release 2022-05-11, XML schemas and a conformance certification program ([1EdTech QTI](https://www.1edtech.org/standards/qti/index)). Template, random and custom operator elements, and the Maxima example, come from the spec text ([QTI 3.0 implementation guide](https://www.imsglobal.org/spec/qti/v3p0/impl)). The IPR section names CITO and HMH with RAND commitments (same page). I found no license statement for the spec text itself: **unverified**.
- Moodle XML types, CDATA rule and no-validation warning ([MoodleDocs: Moodle XML format](https://docs.moodle.org/en/Moodle_XML_format)). STACK questions use the same file format: the STACK library is 4,086 XML files ([tree API](https://api.github.com/repos/maths/moodle-qtype_stack/git/trees/master?recursive=1)).
- Calculated type, dataset limit, function list and tolerance modes ([MoodleDocs: Calculated question type](https://docs.moodle.org/en/Calculated_question_type)). The `formulas` plugin (version 6.4.0, 2026-10-08, GPL header) adds random values and several answer fields ([qtype_formulas](https://github.com/FormulasQuestion/moodle-qtype_formulas)).
- GIFT types and numeric syntax ([MoodleDocs: GIFT format](https://docs.moodle.org/en/GIFT_format)).
- H5P package layout ([H5P specification](https://h5p.org/documentation/developers/h5p-specification)). H5P uses MIT wherever possible; the PHP library carries some GPL third-party code ([H5P licensing](https://h5p.org/licensing)). I found no parametric math content type in H5P.

Better-defined formats outside the standards: Numbas JSON with a JSON Schema, and the STACK API's YAML question dump (section 1). Neither is an exchange standard, but both are documented and machine-readable.

**What it means for us:** reuse Moodle XML as the one import path that matters, because STACK content and the German university pools live in it, and copy the git layout of `qbank_gitsync` (one file per task). Keep our own canonical format, since no standard carries "parameters computed by code, checked by code, hints in steps" portably (QTI's custom operator is engine-specific). Treat QTI 3.0 and H5P as later, lossy export targets. Ignore GIFT and Moodle calculated for new work.

## 4. AI worksheet tools and education MCP servers, 2025 to 2026

### German and international tools

| Tool | What it does | Open source | Reusable task bank | MCP | Source |
|---|---|---|---|---|---|
| fobizz | Worksheet generator "with or without AI", AI chat and custom assistants, handwriting and PDF to text | not stated | free gallery of materials made with fobizz tools; contents not described | not mentioned | [fobizz tools](https://fobizz.com/de/die-fobizz-tools-fuer-schule-und-unterricht/) |
| to teach | Worksheets with "30+ Aufgabentypen" and answer keys; export PDF, DOCX and interactive H5P | not stated | no library described | not mentioned | [to teach](https://to-teach.ai/use-case/de/worksheet) |
| schulKI | Worksheet generator (beta: gap fill, multiple choice, sorting, writing), AI grading of free-text tasks, German servers, models Gemma, Qwen, Llama, ChatGPT, Claude; 12.99 EUR per year (personal, 2M tokens) up to 719.88 EUR per year (school plus) | not stated | not mentioned | no; advertises a "Premium-API" to models | [schulKI](https://schulki.de/) |
| AIS.chat (formerly telli, renamed 2026-05-20) | Free chatbot run by FWU for the 16 Länder, funded by DigitalPakt Schule, used in 12 Länder; custom assistants, class scenarios by QR code | no repository or license mentioned | no | not mentioned | [refmeister](https://www.refmeister.de/ki-tools/telli) |
| Skillsquare, Fiete.ai (FelloFish), Teachino | feedback, correction, material generation | not stated | not described | not mentioned | [Skillsquare comparison](https://www.skillsquare.de/vergleich-ki-tools-fuer-schulen), published by Skillsquare itself, so treat as vendor claims |
| bettermarks | adaptive math exercises for grades 3 to 13, more than 200,000 exercises; closest commercial math competitor | not mentioned | proprietary bank; random parameters and worksheet creation not mentioned | not mentioned | [bettermarks](https://de.bettermarks.com/) |
| MagicSchool | AI generators (worksheet, quiz, lesson plan). Its MCP connector is one-way: one tool, `import_document_to_resource_library`, saves content from Claude or ChatGPT into the teacher's library; OAuth; checked 2026-08-22 | not stated | yes: a per-teacher Resource Library | yes, write-only | [Agentman listing](https://agentman.ai/agentskills/connections/mcp-server/magicschool-ai), [integrations page](https://www.magicschool.ai/integrations) (does not mention it) |
| Brisk | A "Brisk Connector for Claude and ChatGPT" help article exists; the page returned HTTP 403, so function and licensing are **unverified** | unverified | unverified | yes (existence only) | [help article](https://help.briskteaching.com/hc/en-us/articles/50241696224020-Set-up-the-Brisk-Connector-for-Claude-and-ChatGPT) |
| TeacherMatic | "100+ smart generators" (vendor claim) | not stated | not stated | not stated | [teachermatic.com](https://teachermatic.com/) |
| Oak National Academy | Open curriculum data, MCP app and SDK, AI lesson assistant "Aila" (MIT, but "primarily for internal use") | yes: code MIT | yes: lessons, units, quizzes, transcripts under OGL v3.0 | yes: public beta at `mcp.thenational.academy/mcp`, 37 tools (24 generated from the OpenAPI schema, 13 composed), plus resources such as a curriculum model | [ecosystem repo](https://github.com/oaknational/oak-open-curriculum-ecosystem), [Aila](https://github.com/oaknational/oak-ai-lesson-assistant) |

None of the German tools states open source, a shared community task bank, or MCP on its public page. That is an absence on the pages I read, not proof.

### MCP servers on GitHub (searched 2026-10-29)

The topic filter `mcp-server` plus `education` returns 115 repositories ([search](https://api.github.com/search/repositories?q=topic:mcp-server+topic:education)). The pattern is LMS connectors and hobby projects.

| Repository | What it does | License | Stars |
|---|---|---|---|
| [boyuchengz/canvas-mcp](https://github.com/boyuchengz/canvas-mcp), [RohanMuppa/brightspace-mcp-server](https://github.com/RohanMuppa/brightspace-mcp-server), [G36maid/moodle-mcp](https://github.com/G36maid/moodle-mcp), [loyaniu/moodle-mcp](https://github.com/loyaniu/moodle-mcp) | read LMS data (courses, grades, due dates, forums) | MIT; the last has none | 117, 60, 27, 52 |
| [devnull03/webwork-mcp](https://github.com/devnull03/webwork-mcp) | read WeBWorK assignments and progress as a student | none | 0 |
| [sdiehl/sympy-mcp](https://github.com/sdiehl/sympy-mcp), [morluto/jacobian](https://github.com/morluto/jacobian), [toms74209200/mcp-maxima](https://github.com/toms74209200/mcp-maxima) | CAS tools for agents (SymPy, composable math tools, Maxima) | Apache-2.0, MIT, MIT | 85, 339, 3 |
| [ankimcp/anki-mcp-server](https://github.com/ankimcp/anki-mcp-server) | agent reads and writes Anki decks | MIT | 538 |
| [johannesbrandenburger/typst-mcp](https://github.com/johannesbrandenburger/typst-mcp) | helps models write and check Typst | MIT | 186 |
| [kkjzio/mcp-quiz-generator](https://github.com/kkjzio/mcp-quiz-generator) | Markdown quiz questions converted to HTML and Word (2025-08) | MIT | 6 |
| [HumphreySun98/Smart-Study-Agent](https://github.com/HumphreySun98/Smart-Study-Agent) | study agent where FSRS picks timing and the LLM only writes content | MIT | 57 |
| [aicoder2009/khanacademyMCP](https://github.com/aicoder2009/khanacademyMCP) | search and read Khan Academy content (2026-03) | **unverified** | not checked |
| `janschachtschabel/wlo-mcp-server` and `wlo-mcp-sc` | MCP over WirLernenOnline search. Listed on [mcpmarket.com](https://mcpmarket.com/server/wlo) and in search results, but both GitHub URLs returned HTTP 404 on 2026-10-29 | **unverified** | n/a |

I found no MCP server that serves a parametric task bank, hands out hints step by step, or builds a worksheet from stored tasks. This is a negative result from the searches above, not exhaustive.

**What it means for us:** differentiate. The open field is a deterministic task-bank and worksheet-recipe server behind MCP. Everyone else either wraps an LMS, adds one-way import into a closed library (MagicSchool), or lets the model write the tasks. Oak shows the pattern to copy for the tool surface: generate tools from an OpenAPI schema and ship the curriculum model as an MCP resource. German vendors give no sign of an MCP offer yet, so an MCP-first design is early, not late. Ignore the CAS MCP servers as a dependency; we need checking inside our own tools.

## 5. Deterministic learner modeling

| | FSRS | Bayesian Knowledge Tracing (BKT) |
|---|---|---|
| Models | memory of a card: stability S, difficulty D, retrievability from elapsed time | mastery of a skill as a hidden binary state |
| Version | FSRS-6, 21 parameters ([algorithm](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)) | classic model with four parameters (initial knowledge, learn, guess, slip); textbook definition, not re-checked here |
| Rust | `fsrs` 6.6.2, published 2026-08-29, BSD-3-Clause, 431,238 downloads ([crates.io](https://crates.io/crates/fsrs), [Cargo.toml](https://github.com/open-spaced-repetition/fsrs-rs/blob/main/Cargo.toml)) | no maintained crate found; only tiny ones: `learnforge-core` 0.1.0 (22 downloads, BKT and SM-2) and `ryu-tuition` 0.1.14 (37 downloads) ([crates.io search](https://crates.io/api/v1/crates?q=knowledge+tracing)) |
| Other languages | Anki, py-fsrs, ts-fsrs (**unverified**) | pyBKT 1.4.3, MIT, Berkeley ([PyPI](https://pypi.org/project/pyBKT/), [repo](https://github.com/CAHLR/pyBKT)) |
| Needs | review log of (time, rating); defaults work without training | sequence of correct and wrong answers per skill |

- `fsrs-rs` API: `FSRS::default().next_states(previous_state, desired_retention, elapsed_days)` returns the next state and interval for each rating. `compute_parameters` fits parameters from review logs. Dependencies in 6.6.2 are `ndarray`, `rayon`, `rand`, `serde`, `snafu` and `wide`, with no deep-learning framework ([README](https://github.com/open-spaced-repetition/fsrs-rs/blob/main/README.md)). The README also mentions an FSRS-7 cost-conditioned policy; its status is **unverified**.
- A parametric task is a new item every time. FSRS fits cards that repeat unchanged (formulas, definitions, vocabulary). For parametric tasks, track the skill or task template, not the variant.

**What it means for us:** reuse `fsrs` as is for recall items, and write BKT by hand per skill (about 30 lines of Rust, closed-form update). Start logging every attempt now (user, template, seed, correct, hint level, time) so parameters can be fitted later. Ignore bigger knowledge-tracing models (deep or graph based) for v1: they are not deterministic in the sense this project wants.

## What this changes

1. **Task format: a declarative bundle, not code.** One task per file in git: parameter ranges and constraints, derived values (exact rational arithmetic), statement template, answer spec, ordered hints, solution steps, variant note, stored tests. No author-supplied Perl, Maxima or Python on the server (WeBWorK, STACK and PrairieLearn all run author code). Allow a restricted expression language only.
2. **Variants are vetted seeds.** Copy STACK's deploy model: generate N seeds, run the task's tests on each, store the passing seed list, dedupe by variant note. A specified PRNG (not the platform's default) keeps a recipe reproducible across versions.
3. **A three-tier checker in Rust, CAS as a separate process.** Tier 1: exact (integers, rationals, normalized strings, units). Tier 2: random-point numeric equivalence, defaults 5 points and 1E-4 (matches WeBWorK and Numbas). Tier 3: named form checks (factored, expanded, lowest terms, as in STACK) and optional symbolic equivalence through SymPy or Maxima over a pipe or HTTP. Rust has no mature CAS (crates.io search shows only small crates under 4,000 downloads), and keeping GPL engines out of process avoids license entanglement ([crates.io search](https://crates.io/api/v1/crates?q=cas+symbolic)).
4. **License the shared bank CC BY-SA 4.0 and carry provenance.** Every task stores source URL, author, license, import date and checksum. Reject NC sources (OPL, OpenStax 2026, GeoGebra, IM v.360) from the bundled bank. Use OPL's three-stage flow (contributed, pending, approved) for the approval queue.
5. **Importers in this order:** Serlo GraphQL (static tasks, solution steps, 6,136 `Quiz` records; ask Serlo about bulk use first), then STACK Moodle XML (STACK sample library, TH Köln pool, later STACK.nrw), then PDF and scan intake through docling, with the IQB Abitur PDFs as a test corpus. Map STACK tests we cannot run to "unsupported" instead of guessing.
6. **Position: school-level parametric tasks plus an AI-client workflow.** We found no open parametric school pool in German and no MCP server over a task bank. Keep the MCP surface small and deterministic: search tasks, render a variant for a seed, check an answer, hand out the next hint, save and render a recipe. Generate the tools from one OpenAPI schema as Oak does, so the model never writes an answer or a solution.
7. **Interop: Moodle XML in and out for the supported subset, QTI 3.0 and H5P later as lossy exports.** Keep one file per task in git, as `qbank_gitsync` does. Skip GIFT, Moodle calculated and Numbas import for now.
8. **Learner model: log first, model second.** Store an append-only attempt log from day one. Use the `fsrs` crate for recall items and a hand-written BKT per skill for parametric tasks, keyed by template or skill, never by variant.
