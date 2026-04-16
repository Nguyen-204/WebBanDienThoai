#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$ROOT_DIR/storage/app/public/products"
PUBLIC_STORAGE_LINK="$ROOT_DIR/public/storage"

mkdir -p "$TARGET_DIR"

if [ ! -e "$PUBLIC_STORAGE_LINK" ]; then
    ln -s ../storage/app/public "$PUBLIC_STORAGE_LINK"
fi

images=(
    "iphone-15-pro-max-256gb.png|https://cellphones.com.vn/media/catalog/product/i/p/iphone-15-pro-max_3.png"
    "iphone-15-128gb.png|https://cellphones.com.vn/media/catalog/product/i/p/iphone-15-128-gbden.png"
    "iphone-14-128gb.jpg|https://cellphones.com.vn/media/catalog/product/i/p/iphone-14_2_1.jpg"
    "samsung-galaxy-s24-ultra.png|https://cellphones.com.vn/media/catalog/product/s/s/ss-s24-ultra-xam-222.png"
    "samsung-galaxy-a55-5g.png|https://cellphones.com.vn/media/catalog/product/s/a/samsung-galaxy-a55.png"
    "samsung-galaxy-a15.png|https://cellphones.com.vn/media/catalog/product/s/a/samsung-galaxy-a15_1_.png"
    "xiaomi-14-ultra.png|https://cellphones.com.vn/media/catalog/product/x/i/xiaomi-14-ultra_3.png"
    "redmi-note-13-pro-5g.png|https://cellphones.com.vn/media/catalog/product/x/i/xiaomi_redmi_13_pro_5g.png"
    "oppo-find-x7-ultra.jpg|https://cellphones.com.vn/media/catalog/product/e/d/eda006276802c.jpg"
    "oppo-a79-5g.png|https://cellphones.com.vn/media/catalog/product/o/p/oppo-a79-tim.png"
    "vivo-x100-pro.jpg|https://asia-exstatic-vivofs.vivo.com/PSee2l50xoirPK7y/product/1703238415288/zip/img/section4-phone-pro-black.jpg"
    "vivo-y36.png|https://asia-exstatic-vivofs.vivo.com/PSee2l50xoirPK7y/product/1685599852965/zip/img/section6-phone-light.png"
    "realme-gt-5-pro.png|https://cellphones.com.vn/media/catalog/product/r/e/realme-gt-5_1__1.png"
    "realme-c67.png|https://static2.realme.net/images/realme-c67/gtmode/phone.png"
)

for image in "${images[@]}"; do
    filename="${image%%|*}"
    url="${image#*|}"
    output_path="$TARGET_DIR/$filename"
    tmp_path="$output_path.part"

    echo "Downloading $filename"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 \
        -A "Mozilla/5.0" \
        "$url" \
        -o "$tmp_path"
    mv "$tmp_path" "$output_path"
done

echo "Downloaded ${#images[@]} images to $TARGET_DIR"
