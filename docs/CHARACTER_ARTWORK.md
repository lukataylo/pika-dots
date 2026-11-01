# Generated cat artwork

Generated with the built-in GPT image tool, using the user's three-cat illustration as a style reference. Original transparent PNGs are bundled without image processing in Sources/PikaDots/Resources/Characters/.

- focus.png: alert orange cat, white paws, open pill eyes.
- chill.png: relaxed teal cat, closed happy eyes, curled tail.
- explain.png: curious purple cat, two paws and round eyes.

The app scales each image at draw time to its tiny 20-point character view. Drag stretch and landing motion still use the existing native transforms. Custom companions retain the colour-configurable native character rendering.

## Exact prompt set

Shared prompt (replace SUBJECT with the corresponding line below):

Use case: stylized-concept. Create ONE transparent PNG app character asset, using the attached cat illustration only as a style reference. Subject: SUBJECT. Minimal flat solid silhouette, two pointed ears, soft rounded shape, tiny white nose and mouth. Designed to stay legible at 20px tall. No gradients, texture, outlines, lettering, props, window, hand, background or shadow. Centered compact silhouette fills 80% of square canvas; clean antialiased edges and genuine alpha transparency. Cute and calm. Output one character only.

Subjects:

- orange alert cat peeking over an invisible window edge with two little white paws and open white pill eyes
- teal cat curled up asleep, closed white happy eyes, a simple curled tail and two white paws
- purple curious cat peeking over an invisible window edge with two white paws and large simple white dot eyes
