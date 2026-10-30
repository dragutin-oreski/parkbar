import Foundation
import Testing
@testable import ParkBarCore

@Suite struct VaultTests {
    let today = Fixture.today

    @Test func loadsEveryEffortAndNoProblems() {
        let v = Fixture.vault()
        #expect(v.efforts.count == 5)
        #expect(v.problems == [])
        #expect(v.agendas.map(\.person).sorted() == ["Bob", "Me"])
    }

    @Test func listsForTheTabs() {
        let v = Fixture.vault()
        #expect(v.current(today: today).map(\.name) == ["Garden shed", "Bike repair", "New idea"])
        #expect(v.cold(today: today).map(\.name) == ["Old plan"])
        #expect(v.archived.map(\.name) == ["Tax return"])
        #expect(v.rank(of: "New idea") == 4)
        #expect(v.rank(of: "Tax return") == nil)
        #expect(v.dueOrLateCount(today: today) == 1)
    }

    @Test func todosJoinTheirEfforts() {
        let v = Fixture.vault()
        #expect(v.linkedTodos(for: "Garden shed").map(\.text) == ["Shed: book the delivery", "Sam Lee — return the ladder"])
        #expect(v.linkedTodos(for: "Old plan").map(\.text) == ["Old link style"])
        #expect(v.looseTodos.map(\.text) == [
            "Something with no effort at all", "Bob — send the permit scan (asked 2026-10-20)", "the courier will call back sometime",
        ])
    }

    @Test func inboxIsTheOpenTodosUnderInbox() throws {
        #expect(Fixture.vault().inbox.map(\.text) == ["Something with no effort at all"])

        let notes = try TempNotes(["Garden shed": effortFile()])
        try Data("""
        ## Inbox

        - [ ] Plain line
        - [x] Done already
        - [ ] Ship it — `make ship`, then say `done` → [[Garden shed]]
        - [ ] Twice and nowhere — `x` and `x` → [[Garden shed]] [[Garden shed]] [[Nowhere]]

        ## Next

        - [ ] Not in the inbox

        ## INBOX

        - [ ] A second inbox section counts too
        """.utf8).write(to: notes.root.appendingPathComponent("todo.md"))
        let vault = notes.vault
        let inbox = vault.inbox
        #expect(inbox.map(\.text) == ["Plain line", "Ship it — `make ship`, then say `done`", "Twice and nowhere — `x` and `x`",
                                      "A second inbox section counts too"])
        #expect(vault.linkedEfforts(of: inbox[1]) == ["Garden shed"])
        #expect(inbox[1].codeSpans == ["make ship", "done"])
        #expect(vault.linkedEfforts(of: inbox[2]) == ["Garden shed"], "once each, and only efforts that exist")
        #expect(inbox[2].codeSpans == ["x"])
    }

    @Test func missingFolderIsAProblemNotACrash() {
        let v = Vault.load(from: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(v.efforts == [])
        #expect(v.problems.count == 1)
    }

    @Test func obsidianLink() {
        let url = Vault.obsidianURL(for: URL(fileURLWithPath: "/notes/efforts/Search v2 rollout & more.md"))
        #expect(url?.absoluteString == "obsidian://open?path=/notes/efforts/Search%20v2%20rollout%20%26%20more.md")
    }
}

@Suite struct TodoTests {
    @Test func parsesSectionsLinksAndWaiting() {
        let todos = Fixture.vault().todos
        #expect(todos.count == 9)
        let bike = todos.first { $0.text.hasPrefix("Bike") }
        #expect(bike?.linkedEfforts == ["Bike repair"])
        #expect(bike?.section == "Next")
        #expect(todos.filter(\.isWaiting).map(\.waitingOn) == ["Bob", "Sam Lee", nil])
    }

    @Test func wikiLinksAndDisplayText() {
        #expect(TodoList.wikiLinks(in: "a [[One]] b [[Two|alias]] c [[Three#H|x]]") == ["One", "Two", "Three"])
        #expect(TodoList.displayText("Do it → [[One]]") == "Do it")
        #expect(TodoList.displayText("See [[One]] first") == "See [[One]] first")
    }

    /// A copy button offers exactly what the line shows as code: markdown code spans, never backticks
    /// inside a link's address or title.
    @Test func codeSpansAreWhatACopyButtonCopies() {
        #expect(TodoList.codeSpans(in: "Read [manual](https://example.com/`v1) then `make deploy`") == ["make deploy"])
        #expect(TodoList.codeSpans(in: #"Read [instructions](https://example.com "run `make deploy`")"#) == [])
        #expect(TodoList.codeSpans(in: "see [`x`](https://example.com)") == [], "code inside link text is shown as the link")
        #expect(TodoList.codeSpans(in: "say `deploy staging` in that session") == ["deploy staging"])
        #expect(TodoList.codeSpans(in: "run `make a`, then `make b`") == ["make a", "make b"])
        #expect(TodoList.codeSpans(in: "``echo `date` now``") == ["echo `date` now"])
        #expect(TodoList.codeSpans(in: "`` `quoted` ``") == ["`quoted`"], "one space each side is dropped")
        #expect(TodoList.codeSpans(in: "it's `a` and `b") == ["a"], "an unmatched backtick is plain text")
        #expect(TodoList.codeSpans(in: "``two`` then `one`") == ["two", "one"])
        #expect(TodoList.codeSpans(in: #"escaped \`not code\` here"#) == [])
        #expect(TodoList.codeSpans(in: "blank `  ` span") == [])
        #expect(TodoList.codeSpans(in: "no code at all") == [])
    }
}

@Suite struct AgendaListTests {
    @Test func groupsAndTitles() throws {
        let agenda = try #require(Fixture.vault().agendas.first { $0.person == "Bob" })
        #expect(agenda.groups.map(\.heading) == ["Waiting on Bob", "To ask"])
        #expect(agenda.groups[0].items == ["Permit scan", "Ladder"])
        #expect(agenda.groups[1].items == ["How the roof load is calculated"])
        #expect(agenda.itemCount == 3)
    }
}

@Suite struct PeopleTests {
    @Test func onePersonPerName() {
        let people = Fixture.vault().people()
        #expect(people.first?.name == "Me")
        #expect(Set(people.map(\.name)) == ["Me", "Bob", "Alice", "Erin", "Sam Lee"])
        #expect(!people.contains { $0.name == "Carol" }, "Carol's only question is in an archived effort")
    }

    @Test func bobGetsQuestionsWaitingAndAgenda() throws {
        let bob = try #require(Fixture.vault().people().first { $0.name == "Bob" })
        #expect(bob.questionsByEffort.map(\.effort) == ["Garden shed", "Old plan"])
        #expect(bob.questionsByEffort[0].questions.count == 2, "the ticked one is left out")
        #expect(bob.waiting.count == 1)
        #expect(bob.agenda?.fileName == "BOB-TOPICS.md")
        #expect(bob.openCount == 4)
    }

    @Test func meHoldsDecisionsAndTheProductList() throws {
        let me = try #require(Fixture.vault().people().first { $0.name == "Me" })
        #expect(me.questions.map(\.question.text) == ["Paint now or in spring"])
        #expect(me.agenda?.fileName == "MY-TOPICS.md")
    }
}
