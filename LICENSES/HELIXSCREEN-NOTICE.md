# HelixScreen notice

NebulaOS builds the K1 variant of [HelixScreen](https://github.com/prestonbrown/helixscreen)
from the pinned commit recorded in `manifests/dependencies.conf` and installs it under
`/opt/helixscreen`.

HelixScreen is distributed under GPL-3.0-or-later. Its `lib/helix-xml/` component carries the
upstream MIT exception described by that repository's source headers. The corresponding source
checkout and license files are fetched as part of the reproducible build process.
