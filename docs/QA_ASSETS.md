# QA image provenance

Development UI verification uses **Golden Retriever adult.jpg**, a 5,488×3,662 photograph by **Johan Spaedtke / Dgse87**, obtained from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Golden_Retriever_adult.jpg).

The author released it under [CC0 1.0 Universal Public Domain Dedication](https://creativecommons.org/publicdomain/zero/1.0/). The source page explicitly permits copying, modification and commercial use. This is a QA asset, not a copied competitor artwork. The original download resides under ignored `.build/qa-images/Golden-Retriever.jpg`, is not bundled into either app, and is not automatically downloaded by Framepebble. Screenshots may show this photo inside actual running interfaces.

Automated tests generate their own small raster fixtures and deterministic noise. No external photo download is required to build or run the automated suite. No third-party software/model is distributed.

The same CC0 original was used for the toolbox/opaque-mask/review screenshots and copied into the isolated `.build/automation-QA/Input` folder. Live automation produced a 1024×1024 JPEG; both original and incoming copy retained SHA-256 `7b4cd5b81d8ff5bc36e4aa80682135715d5ad71a56705426ea28079e3a5ef8c3`. The test workflow was paused and its completed output retained. No user's private photograph was uploaded or sent to another application during QA. A reviewed masked copy was saved to Simulator Photos with existing add-only authorization.
