import Foundation

enum SampleSyllabi: String, CaseIterable, Identifiable {
    case simple = "A — Simple"
    case complicated = "B — Complicated"
    case ambiguous = "C — Ambiguous"
    var id: String { rawValue }
    var text: String {
        switch self {
        case .simple:
            """
            CS 101 — Introduction to Programming
            Fall 2026. Instructor: Dr. Mira Chen.
            Grading: Homework 30%, Midterm Exam 25%, Final Exam 35%, Participation 10%.
            Midterm Exam: October 15, 2026. Final Exam: December 10, 2026.
            Project 1 is due September 24, 2026.
            """
        case .complicated:
            """
            STAT 210 — Applied Statistics
            Spring 2027. Instructor: Professor Alex Rivera.
            Grading: Homework 20%, Quizzes 15%, Labs 20%, Project 20%, Midterm 10%, Final 15%.
            The lowest two quiz scores are dropped. No homework scores are dropped.
            Homework is usually due each Friday by 11:59 p.m. Quizzes normally occur on Mondays.
            Midterm is tentatively scheduled for March 11, 2027. Final exam date is tentatively May 6, 2027.
            The project report is due April 23, 2027.
            Up to 2 extra credit points may be earned through optional review exercises.
            """
        case .ambiguous:
            """
            HIST 150 — Cities and Memory
            Instructor: Dr. Taylor Brooks.
            Essays count for 40% of the course grade. Participation counts for 20%.
            A final project will be due near the end of term; the exact date will be announced later.
            Short reading checks may occur occasionally. Late work may be considered case by case.
            """
        }
    }
}
