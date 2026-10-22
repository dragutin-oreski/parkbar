import Foundation

/// Everything one person is involved in: questions to ask them, what they owe, their agenda list.
public struct Person: Equatable, Identifiable, Sendable {
    public struct AskedQuestion: Equatable, Identifiable, Sendable {
        public let effort: String
        public let question: EffortBody.Question
        public var id: String { "\(effort)#\(question.line)" }
    }

    public let name: String
    /// Open questions only, grouped later by effort; active efforts first.
    public let questions: [AskedQuestion]
    public let waiting: [Todo]
    public let agenda: AgendaList?

    public var id: String { name }
    public var openCount: Int { questions.count + waiting.count }

    public var questionsByEffort: [(effort: String, questions: [EffortBody.Question])] {
        var order: [String] = []
        var grouped: [String: [EffortBody.Question]] = [:]
        for q in questions {
            if grouped[q.effort] == nil { order.append(q.effort) }
            grouped[q.effort, default: []].append(q.question)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }
}

public extension Vault {
    /// One entry per person named in a question, a waiting item or an agenda list.
    /// You (the config's `meName`) come first, then by open count, then by name. Archived efforts' questions
    /// are left out.
    func people() -> [Person] {
        var questions: [String: [Person.AskedQuestion]] = [:]
        for effort in activeOrder {
            for q in effort.body.questions where !q.isChecked {
                for name in q.people { questions[name, default: []].append(.init(effort: effort.name, question: q)) }
            }
        }
        var waiting: [String: [Todo]] = [:]
        for todo in todos where todo.isWaiting {
            if let name = todo.waitingOn { waiting[name, default: []].append(todo) }
        }
        let agendaByPerson = Dictionary(agendas.map { ($0.person, $0) }, uniquingKeysWith: { a, _ in a })

        let names = Set(questions.keys).union(waiting.keys).union(agendaByPerson.keys)
        let people = names.map { name in
            Person(name: name, questions: questions[name] ?? [], waiting: waiting[name] ?? [], agenda: agendaByPerson[name])
        }
        return people.sorted { a, b in
            if (a.name == config.meName) != (b.name == config.meName) { return a.name == config.meName }
            if a.openCount != b.openCount { return a.openCount > b.openCount }
            return a.name < b.name
        }
    }
}
