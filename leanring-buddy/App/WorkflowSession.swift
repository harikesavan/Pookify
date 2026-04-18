import Foundation

enum GuidedWorkflowPhase: String, Codable {
    case planning
    case awaitingUserAction
    case verifying
    case blocked
    case completed
}

struct GuidedWorkflowStep: Codable, Identifiable {
    let id: Int
    let goal: String
    let visualAnchor: String
    let successCriteria: String
}

struct GuidedWorkflowPlan: Codable {
    let objective: String
    let steps: [GuidedWorkflowStep]
    let stopCondition: String
}

struct GuidedWorkflowVerification: Codable {
    let status: String
    let evidence: [String]
    let mismatchType: String?
    let nextAction: String?
}

struct GuidedWorkflowSession {
    let objective: String
    let steps: [GuidedWorkflowStep]
    let stopCondition: String
    var currentStepIndex: Int
    var phase: GuidedWorkflowPhase
    var lastSpokenInstruction: String?
    var lastVerificationEvidence: [String]

    var currentStep: GuidedWorkflowStep? {
        guard currentStepIndex >= 0 && currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var stepProgressText: String {
        guard !steps.isEmpty else { return "0/0" }
        return "\(min(currentStepIndex + 1, steps.count))/\(steps.count)"
    }
}
