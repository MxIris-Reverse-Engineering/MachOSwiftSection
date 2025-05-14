import Foundation

struct AnyLocatableLayoutWrapper<Layout>: LocatableLayoutWrapper {
    let offset: Int
    var layout: Layout

    init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
