#!/bin/bash

# Clean up any existing containers first
echo "Cleaning up any existing containers..."
docker rm -f gotenberg-test tesseract-test poppler-test 2>/dev/null || true

# PDF Compression with Gotenberg
echo "Starting Gotenberg container..."
docker run --rm -d -p 3000:3000 --name gotenberg-test gotenberg/gotenberg:8

# Wait for container to be ready
echo "Waiting for Gotenberg to start..."
sleep 10

echo "Compressing PDF with Gotenberg (LibreOffice)..."
curl -v \
  --request POST http://localhost:3000/forms/libreoffice/convert \
  --form files=@"1900_1_Consolidated_Fund_No_1_Act_1900.pdf" \
  --form losslessImageCompression=false \
  --form quality=30 \
  --form reduceImageResolution=true \
  --form maxImageResolution=75 \
  -o "1900_compressed.pdf"

echo "Checking compressed file:"
file 1900_compressed.pdf
ls -lh 1900_compressed.pdf

# Clean up Gotenberg container
echo "Stopping Gotenberg container..."
docker rm -f gotenberg-test

# Convert PDF to images for OCR
echo "Converting PDF to images..."
docker run --rm --name poppler-test \
  -v "$(pwd):/work" \
  -w /work \
  minidocks/poppler \
  pdftoppm -png 1900_1_Consolidated_Fund_No_1_Act_1900.pdf page

# OCR with Tesseract on each page
echo "Running OCR with Tesseract..."
for image in page-*.png; do
  if [ -f "$image" ]; then
    echo "Processing $image..."
    docker run --rm --name tesseract-test \
      -v "$(pwd)/$image:/tmp/image.png" \
      jitesoft/tesseract-ocr /tmp/image.png stdout >> 1900_ocr_text.txt
  fi
done

# Clean up image files
rm -f page-*.png

# Compare results
echo ""
echo "=== RESULTS ==="
echo "Original file size:"
ls -lh "1900_1_Consolidated_Fund_No_1_Act_1900.pdf"
echo "Compressed file size:"
ls -lh "1900_compressed.pdf" 2>/dev/null || echo "Compression failed"
echo "OCR output:"
ls -lh "1900_ocr_text.txt" 2>/dev/null || echo "OCR failed"

# Show first few lines of OCR text
if [ -f "1900_ocr_text.txt" ]; then
  echo ""
  echo "First few lines of OCR text:"
  head -10 "1900_ocr_text.txt"
fi
