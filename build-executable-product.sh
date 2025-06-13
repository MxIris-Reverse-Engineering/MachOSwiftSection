# 分别构建不同架构
swift build -c release --arch x86_64 --product swift-section
swift build -c release --arch arm64 --product swift-section

# 检查目录是否存在
if [ ! -d "./Products" ]; then
    mkdir Products
fi

# 使用 lipo 合并二进制文件
lipo -create \
    .build/x86_64-apple-macosx/release/swift-section \
    .build/arm64-apple-macosx/release/swift-section \
    -output ./Products/swift-section



