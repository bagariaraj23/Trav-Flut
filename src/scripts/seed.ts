import { prisma } from "@/lib/prisma";

async function main() {
  console.log("🌱 Starting database seeding...");

  // Create sample users
  const user1 = await prisma.user.upsert({
    where: { email: "bagariaraj23@gmail.com" },
    update: {},
    create: {
      email: "bagariaraj23@gmail.com",
      username: "raj_bagaria",
      name: "Raj Bagaria",
      isPrivate: false,
    },
  });

  const user2 = await prisma.user.upsert({
    where: { email: "kunal@example.com" },
    update: {},
    create: {
      email: "kunal@example.com",
      username: "kunal_kabra",
      name: "Kunal kabra",
      isPrivate: false,
    },
  });

  const user3 = await prisma.user.upsert({
    where: { email: "raghav@example.com" },
    update: {},
    create: {
      email: "raghav@example.com",
      username: "raghav_kashyap",
      name: "Raghav Kashyap",
      isPrivate: false,
    },
  });

  console.log("✅ Users created:", {
    user1: user1.username,
    user2: user2.username,
    user3: user3.username,
  });

  // Create follow relationship
  await prisma.follow.upsert({
    where: {
      followerId_followeeId: {
        followerId: user1.id,
        followeeId: user2.id,
      },
    },
    update: {},
    create: {
      followerId: user1.id,
      followeeId: user2.id,
    },
  });

  await prisma.follow.upsert({
    where: {
      followerId_followeeId: {
        followerId: user1.id,
        followeeId: user3.id,
      },
    },
    update: {},
    create: {
      followerId: user1.id,
      followeeId: user3.id,
    },
  });

  console.log("✅ Follow relationships created");

  // Create sample trips
  const trip1 = await prisma.trip.create({
    data: {
      userId: user2.id,
      title: "Tokyo Adventure",
      destinations: ["Tokyo, Japan"],
      startDate: new Date("2024-01-15"),
      endDate: new Date("2024-01-22"),
      status: "ENDED",
      mood: "CULTURAL",
      type: "SOLO",
      coverMediaId: null,
      description:
        "Exploring the vibrant culture, incredible food, and modern marvels of Tokyo",
    },
  });

  const trip2 = await prisma.trip.create({
    data: {
      userId: user3.id,
      title: "Bali Escape",
      destinations: ["Bali, Indonesia"],
      startDate: new Date("2024-02-10"),
      endDate: new Date("2024-02-17"),
      status: "ENDED",
      mood: "RELAXED",
      type: "SOLO",
      coverMediaId: null,
      description: "Island paradise, temples, and incredible sunsets",
    },
  });

  const trip3 = await prisma.trip.create({
    data: {
      userId: user2.id,
      title: "Paris Weekend",
      destinations: ["Paris, France"],
      startDate: new Date("2024-03-01"),
      endDate: new Date("2024-03-03"),
      status: "ONGOING",
      mood: "CULTURAL",
      type: "COUPLE",
      coverMediaId: null,
      description: "Romantic weekend in the City of Light",
    },
  });

  console.log("✅ Trips created:", {
    trip1: trip1.title,
    trip2: trip2.title,
    trip3: trip3.title,
  });

  // Create sample final posts
  const finalPost1 = await prisma.tripFinalPost.create({
    data: {
      tripId: trip1.id,
      userId: trip1.userId,
      summaryText:
        "An incredible week exploring Tokyo's vibrant culture, incredible food, and modern marvels. From the organized chaos of Shibuya Crossing to the peaceful serenity of Senso-ji Temple, every moment was filled with wonder.",
      curatedMedia: [
        "https://images.pexels.com/photos/2506923/pexels-photo-2506923.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/1907228/pexels-photo-1907228.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/1239291/pexels-photo-1239291.jpeg?auto=compress&cs=tinysrgb&w=600",
      ],
      caption: "Tokyo stole my heart 🇯🇵✨",
      isPublished: true,
    },
  });

  const finalPost2 = await prisma.tripFinalPost.create({
    data: {
      tripId: trip2.id,
      userId: trip2.userId,
      summaryText:
        "A week of pure bliss in Bali. From the spiritual temples of Ubud to the pristine beaches of Nusa Penida, this island paradise exceeded all expectations. The sunsets were absolutely magical.",
      curatedMedia: [
        "https://images.pexels.com/photos/3073666/pexels-photo-3073666.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/3889843/pexels-photo-3889843.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/3889845/pexels-photo-3889845.jpeg?auto=compress&cs=tinysrgb&w=600",
      ],
      caption: "Bali vibes 🌴☀️",
      isPublished: true,
    },
  });

  console.log("✅ Final posts created:", {
    post1: finalPost1.id,
    post2: finalPost2.id,
  });

  console.log("🎉 Database seeding completed successfully!");
}

main()
  .catch((e) => {
    console.error("❌ Error during seeding:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
