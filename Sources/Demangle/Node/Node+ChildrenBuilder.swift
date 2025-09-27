import Foundation
import FoundationToolbox

extension Node {
    package convenience init(kind: Kind, contents: Contents = .none, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) {
        self.init(kind: kind, contents: contents, children: childrenBuilder())
    }
    
    package convenience init(kind: Kind, text: String, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) {
        self.init(kind: kind, contents: .text(text), children: childrenBuilder())
    }
    
    package convenience init(kind: Kind, index: UInt64, @ArrayBuilder<Node> childrenBuilder: () -> [Node]) {
        self.init(kind: kind, contents: .index(index), children: childrenBuilder())
    }
}
