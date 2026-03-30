import SwiftUI
 
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Main View
struct ContentView: View {
    
    @State private var duaText: String = ""
    @State private var selectedDua: DuaReceiver? = nil
    @State private var showModal = false
    
    @ObservedObject private var duaService = DuaService.shared
    
    // MARK: - Action
    func generateDua() {
        let trimmed = duaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        Task {
            await duaService.generateDuas(input: DuaSender(inputtedDuaText: trimmed))
            duaText = ""
        }
    }
    
    // MARK: - Colors
    let goldGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(red: 200/255, green: 155/255, blue: 60/255),
            Color(red: 169/255, green: 119/255, blue: 34/255)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        
        ZStack {
            
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: Title
                    Text("Write Your Dua")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("The Aim ?")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // MARK: Input
                    VStack(spacing: 8) {
                        
                        TextEditor(text: $duaText)
                            .frame(height: 150)
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(12)
                        
                        Text("Example: \"Oh Allah, grant me success in...\"")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 20)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(16)
                    
                    // MARK: Button
                    Button(action: generateDua) {
                        Text("Bespoke My Dua")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(goldGradient)
                            )
                    }
                    
                    Divider()
                    
                    // MARK: Cards
                    VStack(alignment: .leading, spacing: 12) {
                        
                        Text("Your Duas")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        if let errorMessage = duaService.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.footnote)
                        }
                        
                        if duaService.isLoading {
                            ProgressView("Generating...")
                                .padding(.vertical, 8)
                        }
                        
                        if duaService.duas.isEmpty && !duaService.isLoading {
                            Text("Write your heart’s dua ✨")
                                .foregroundColor(.gray)
                                .italic()
                                .frame(maxWidth: .infinity)
                        }
                        
                        ForEach(duaService.duas) { item in
                            DuaCard(
                                item: item,
                                onDelete: {
                                    duaService.duas.removeAll { $0.id == item.id }
                                },
                                selectedDua: $selectedDua,
                                showModal: $showModal
                            )
                        }
                    }
                    
                    Spacer(minLength: 80)
                }
                .padding()
            }
            
            VStack {
                Spacer()
                BottomNavBar()
            }
        }
        .sheet(isPresented: $showModal) {
            if let dua = selectedDua {
                ExplanationModal(dua: dua)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - Card
struct DuaCard: View {
    let item: DuaReceiver
    let onDelete: () -> Void
    
    @Binding var selectedDua: DuaReceiver?
    @Binding var showModal: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            Text(item.duaText)
                .font(.body)
            
            HStack {
                Spacer()
                
                Button(action: {
                    selectedDua = item
                    showModal = true
                }) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(Color(red: 200/255, green: 155/255, blue: 60/255))
                        .padding(6)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                
                Button(action: {
#if canImport(UIKit)
                    UIPasteboard.general.string = item.duaText
#else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.duaText, forType: .string)
#endif
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        .shadow(color: .white.opacity(0.6), radius: 6, y: -2)
    }
}

// MARK: - Modal
struct ExplanationModal: View {
    let dua: DuaReceiver
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                        .padding(10)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            
            Text("Have no doubt, Allah is...")
                .font(.title2)
                .fontWeight(.semibold)
            
            let goldGradient = LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 200/255, green: 155/255, blue: 60/255),
                    Color(red: 169/255, green: 119/255, blue: 34/255)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            ForEach(dua.explanations) { exp in
                VStack(alignment: .leading, spacing: 6) {
                    
                    Text(exp.name)
                        .font(.headline)
                        .foregroundStyle(goldGradient)
                    
                    Text(exp.explanation)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .cornerRadius(12)
                .frame(maxWidth: .infinity)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Navbar
struct BottomNavBar: View {
    var body: some View {
        ZStack {
            HStack { Spacer() }
                .frame(height: 60)
#if canImport(UIKit)
                .background(Color(.systemBackground))
#else
                .background(Color(NSColor.windowBackgroundColor))
#endif
                .shadow(radius: 5)
            
            Button(action: {}) {
                Image(systemName: "house.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(Color(red: 34/255, green: 70/255, blue: 50/255))
                    .clipShape(Circle())
            }
            .offset(y: -20)
        }
    }
}

#Preview {
    ContentView()
}
