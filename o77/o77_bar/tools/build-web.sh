#!/bin/sh
# web/bar.html is the source (also the browser preview). The game loads web/index.html,
# which is the same page wrapped in a full HTML document.
cd "$(dirname "$0")/.." || exit 1
{ printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n</head>\n<body>\n'
  cat web/bar.html
  printf '\n</body>\n</html>\n'; } > web/index.html
echo "wrote web/index.html"
