import MCP

let session = BinarySession()
let toolHandler = ToolHandler(session: session)

let server = Server(
    name: "swift-section",
    version: "0.8.0",
    capabilities: .init(
        logging: .init(),
        tools: .init(listChanged: false)
    )
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: ToolDefinitions.allTools)
}

await server.withMethodHandler(CallTool.self) { params in
    await toolHandler.handle(params)
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
