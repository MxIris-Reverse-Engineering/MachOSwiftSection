swift build -c release --arch x86_64 --product swift-section
swift build -c release --arch arm64 --product swift-section

if [ ! -d "./Products" ]; then
    mkdir Products
fi

lipo -create \
    .build/x86_64-apple-macosx/release/swift-section \
    .build/arm64-apple-macosx/release/swift-section \
    -output ./Products/swift-section



