//
//  ContentView.swift
//  bespokeDua
//

import SwiftUI

struct ContentView: View {
    
    @State private var duaText: String = ""
    @State private var duas: [String] = []
    
    // MARK: - Action
    func generateDua() {
        if !duaText.isEmpty {
            duas.append(duaText)
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
    
    let darkGreen = Color(
        red: 11/255,
        green: 93/255,
        blue: 59/255
    )
    
    var body: some View {
        
        ZStack {
            
            // MARK: Main Content
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: Title
                    Text("Write Your Dua")
                        .font(.title)
                        .fontWeight(.semibold)
                        .padding(.top, 10)
                    
                    Text("The Aim ?")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // MARK: Input Card
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
                    .padding(.bottom, 30)
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
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    
                    Divider()
                        .padding(.vertical, 6)
                    
                    // MARK: List
                    VStack(alignment: .leading, spacing: 12) {
                        
                        Text("Your Duas")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Type your dua above and click the button to generate personalised versions.")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .italic()
                            .padding()
                        
//                        ForEach(duas, id: \.self) { dua in
//                            Text(dua)
//                                .padding()
//                                .frame(maxWidth: .infinity, alignment: .leading)
//                                .background(Color.gray.opacity(0.06))
//                                .cornerRadius(12)
//                        }
                        ForEach(duas, id: \.self) { dua in
                            DuaCard(
                                title: "Salam (The Source of Peace)",
                                explanation: "This Name reflects peace and protection.",
                                dua: dua
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 80) // prevents overlap with navbar
                }
                .padding()
            }
            
            // MARK: Bottom Navbar
            VStack {
                Spacer()
                BottomNavBar()
            }
        }
        .background(Color.white)
    }
}

// MARK: - Bottom Nav Bar
struct BottomNavBar: View {
    var body: some View {
        ZStack {
            
            // Background bar
            HStack {
                Spacer()
            }
            .frame(height: 60)
            .background(Color(.systemBackground))
            .shadow(radius: 5)
            
            // Center Home Button
            Button(action: {
                print("Home tapped")
            }) {
                Image(systemName: "house.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(Color(red: 34/255, green: 70/255, blue: 50/255)) // forest green
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .offset(y: -20)
        }
    }
}

struct DuaCard: View {
    let title: String
    let explanation: String
    let dua: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Title (Name)
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.brown)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                }
            }
            
            // Explanation
            Text(explanation)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Divider()
            
            // Dua text
            Text(dua)
                .font(.body)
                .foregroundColor(.black)
            
            // Actions
            HStack {
                Spacer()
                
                Button(action: {}) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(red: 245/255, green: 240/255, blue: 230/255)) // warm beige
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

#Preview {
    ContentView()
}
