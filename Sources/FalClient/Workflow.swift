
public enum WorkflowEventType: String, Codable {
    case submit
    case completion
    case output
    case error
}

protocol WorkflowEvent: Codable {
    var type: WorkflowEventType { get }
    var nodeId: String { get }
}

struct WorkflowSubmitEvent: WorkflowEvent {
    let type: WorkflowEventType = .submit
    let nodeId: String
    let appId: String
    let requestId: String

    enum CodingKeys: String {
        case type
        case nodeId = "node_id"
        case appId = "app_id"
        case requestId = "request_id"
    }
}

struct WorkflowOutputEvent: WorkflowEvent {
    let type: WorkflowEventType = .output
    let nodeId: String

    enum CodingKeys: String {
        case type
        case nodeId = "node_id"
    }
}

struct WorkflowCompletionEvent: WorkflowEvent {
    let type: WorkflowEventType = .completion
    let nodeId: String
    let appId: String
    let output: Payload

    enum CodingKeys: String {
        case type
        case nodeId = "node_id"
        case appId = "app_id"
        case output
    }
}

struct WorkflowErrorEvent: WorkflowEvent {
    let type: WorkflowEventType = .error
    let nodeId: String
    let message: String
    // TODO: decode the underlying error to a more specific type
    let error: Payload
}

public enum WorkflowEventData {
    case submit(WorkflowSubmitEvent)
    case completion(WorkflowCompletionEvent)
    case output(WorkflowOutputEvent)
    case error(WorkflowErrorEvent)
}
