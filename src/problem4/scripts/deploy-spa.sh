#!/usr/bin/env bash
# Deploy an SPA build to S3 + CloudFront with instant-rollback layout.
#
# Layout:  s3://bucket/releases/<sha>/...   (immutable, kept for rollback)
#          s3://bucket/index.html           (tiny pointer, no-cache)
#
# Order matters: upload hashed assets BEFORE the index.html that references
# them, so a user never receives an index pointing at missing files.
set -euo pipefail

DIST_DIR=$1 BUCKET=$2 CF_DIST_ID=$3 VERSION=$4
RELEASE_PREFIX="releases/${VERSION}"

if aws s3 ls "s3://${BUCKET}/${RELEASE_PREFIX}/index.html" >/dev/null 2>&1; then
  echo "Release ${VERSION} already in S3 (rollback path) — skipping asset upload"
else
  # 1) Hashed assets: cache forever (filenames change per content)
  aws s3 sync "${DIST_DIR}" "s3://${BUCKET}/${RELEASE_PREFIX}/" \
    --exclude index.html \
    --cache-control "public,max-age=31536000,immutable"
  # 2) The release's own index.html
  aws s3 cp "${DIST_DIR}/index.html" "s3://${BUCKET}/${RELEASE_PREFIX}/index.html" \
    --cache-control "no-cache"
fi

# 3) Atomically point the live site at this release
aws s3 cp "s3://${BUCKET}/${RELEASE_PREFIX}/index.html" "s3://${BUCKET}/index.html" \
  --cache-control "no-cache"

# 4) Invalidate only the pointer — assets are immutable and never invalidated
aws cloudfront create-invalidation \
  --distribution-id "${CF_DIST_ID}" \
  --paths "/index.html" "/"

echo "Deployed ${VERSION} -> ${BUCKET}"
