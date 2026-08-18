import Foundation
import FoundationModels
import MulticaKit

/// The tools the on-device model can call.
///
/// Every one is a single hop into ``WorkspaceStore``'s command layer, so the
/// behaviour lives in plain `@MainActor` code and these types stay declarative:
/// a name, a description the model reads, and the arguments it may fill in.
enum WorkspaceTools {
    static func all(store: WorkspaceStore, delegation: any AgentDelegation) -> [any Tool] {
        [
            ListTasksTool(store: store),
            CreateTaskTool(store: store),
            MoveTaskTool(store: store),
            ListProjectsTool(store: store),
            CreateProjectTool(store: store),
            DelegateToAgentTool(delegation: delegation),
        ]
    }
}

struct ListTasksTool: Tool {
    let name = "listTasks"
    let description = """
        Look at the tasks in the workspace. Use this before answering anything \
        about what is planned, in flight, waiting for review, or finished.
        """

    @Generable
    struct Arguments {
        @Guide(description: "One of: planned, ongoing, staged, finished. Omit for every lane.")
        var lane: String?
        @Guide(description: "Project name to narrow to. Omit for the whole workspace.")
        var project: String?
    }

    let store: WorkspaceStore

    func call(arguments: Arguments) async throws -> String {
        await store.describeTasks(lane: arguments.lane, project: arguments.project)
    }
}

struct ListProjectsTool: Tool {
    let name = "listProjects"
    let description = "List the projects in the workspace with how far along each one is."

    @Generable
    struct Arguments {}

    let store: WorkspaceStore

    func call(arguments: Arguments) async throws -> String {
        await store.describeProjects()
    }
}

struct CreateTaskTool: Tool {
    let name = "createTask"
    let description = """
        Create a task in the workspace. Use it whenever the person asks for \
        something to be written down, drafted, planned, or added.
        """

    @Generable
    struct Arguments {
        @Guide(description: "Short imperative title, at most a dozen words.")
        var title: String
        @Guide(description: "Fuller description in Markdown, carrying the detail from the conversation.")
        var notes: String?
        @Guide(description: "Project name to file it under. Omit if the person did not name one.")
        var project: String?
        @Guide(description: "One of: planned, ongoing, staged, finished. Defaults to planned.")
        var lane: String?
        @Guide(description: "One of: none, low, medium, high, urgent.")
        var priority: String?
    }

    let store: WorkspaceStore

    func call(arguments: Arguments) async throws -> String {
        await store.createTask(
            title: arguments.title,
            notes: arguments.notes,
            project: arguments.project,
            lane: arguments.lane,
            priority: arguments.priority
        )
    }
}

struct MoveTaskTool: Tool {
    let name = "moveTask"
    let description = """
        Move an existing task into another lane — for example when the person \
        says something is done, started, or ready for review.
        """

    @Generable
    struct Arguments {
        @Guide(description: "The task identifier such as CRATCH-4, or enough of its title to find it.")
        var task: String
        @Guide(description: "One of: planned, ongoing, staged, finished.")
        var lane: String
    }

    let store: WorkspaceStore

    func call(arguments: Arguments) async throws -> String {
        await store.moveTask(matching: arguments.task, toLane: arguments.lane)
    }
}

struct CreateProjectTool: Tool {
    let name = "createProject"
    let description = "Create a project to group tasks under. Only when the person asks for a new one."

    @Generable
    struct Arguments {
        @Guide(description: "The project name.")
        var title: String
        @Guide(description: "One sentence on what the project is for.")
        var summary: String?
        @Guide(description: "A single emoji that fits the project.")
        var icon: String?
    }

    let store: WorkspaceStore

    func call(arguments: Arguments) async throws -> String {
        await store.createProjectNamed(arguments.title, summary: arguments.summary, icon: arguments.icon)
    }
}

/// What ``DelegateToAgentTool`` needs from the call screen, kept as a protocol
/// so the tool never reaches into the view model.
protocol AgentDelegation: Sendable {
    /// Hands a question to a server agent and returns immediately with a
    /// sentence to say. The answer arrives later, out of band.
    func handOff(question: String, to agentName: String?) async -> String
}

struct DelegateToAgentTool: Tool {
    let name = "askMulticaAgent"
    let description = """
        Hand a question or a piece of work to a Multica agent on the server. \
        Use it when the answer needs the codebase, the web, tools, or more \
        reasoning than you can do on device — for example "draft the full plan \
        and put it in project X". The agent replies in a minute or two, not \
        immediately, so say that you have handed it over and carry on.
        """

    @Generable
    struct Arguments {
        @Guide(description: "The full request for the agent, written so it stands on its own.")
        var request: String
        @Guide(description: "Name of the agent to ask. Omit to use the workspace default.")
        var agent: String?
    }

    let delegation: any AgentDelegation

    func call(arguments: Arguments) async throws -> String {
        await delegation.handOff(question: arguments.request, to: arguments.agent)
    }
}
