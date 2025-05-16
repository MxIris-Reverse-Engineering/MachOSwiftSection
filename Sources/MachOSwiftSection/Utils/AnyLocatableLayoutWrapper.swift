import Foundation

struct AnyLocatableLayoutWrapper<Layout>: LocatableLayoutWrapper {
    var layout: Layout
    let offset: Int
    
    init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
