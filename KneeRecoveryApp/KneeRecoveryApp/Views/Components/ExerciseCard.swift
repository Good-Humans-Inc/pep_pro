import SwiftUI

struct ExerciseCard: View {
    let exercise: Exercise
    
    var body: some View {
        HStack {
            // Exercise image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                if let imageURL = exercise.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "figure.walk")
                                .font(.system(size: 30))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                } else {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 30))
                }
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                
                Text(exercise.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Image(systemName: "clock")
                    Text("\(Int(exercise.duration / 60)) min")
                    
                    Spacer()
                    
                    Image(systemName: "figure.walk")
                    Text("\(exercise.targetJoints.count) targets")
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 8)
    }
}

struct ExerciseCard_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseCard(exercise: Exercise.examples[0])
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
