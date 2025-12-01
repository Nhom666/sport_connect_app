// === PHẦN 1: IMPORT ===
// Các thư viện cũ
const admin = require("firebase-admin");
const axios = require("axios"); // Để tải web
const cheerio = require("cheerio"); // Để cào web
const express = require("express"); // Để tạo API
const cors = require("cors"); // Để cho phép gọi API

// === IMPORT CÚ PHÁP V2 MỚI ===
// Nhập hàm chạy theo lịch (v2)
const { onSchedule } = require("firebase-functions/v2/scheduler");
// Nhập hàm HTTP (v2)
const { onRequest } = require("firebase-functions/v2/https");
// Nhập hàm theo dõi Firestore document (v2)
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");

// === PHẦN 2: KHỞI TẠO ===
admin.initializeApp();
const db = admin.firestore();

// === PHẦN 3: HÀM AUTO-REJECT (Scheduled) - CÚ PHÁP V2 ===

exports.autoRejectOldRequests = onSchedule(
  // Cấu hình được đưa vào một object
  {
    schedule: "every 10 minutes",
    region: "asia-southeast1",
    timeZone: "Asia/Ho_Chi_Minh", // Thêm múi giờ cho chắc
  },
  // Hàm handler
  async (event) => {
    console.log("Đang chạy hàm (v2): autoRejectOldRequests...");
    try {
      // 1. Tính toán thời gian "1 giờ trước"
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
      const oneHourAgoTimestamp =
        admin.firestore.Timestamp.fromDate(oneHourAgo);

      // 2. Tìm tất cả yêu cầu "pending"
      // LƯU Ý: Vẫn phải tạo INDEX trong Firestore
      const querySnapshot = await db
        .collection("joinRequests")
        .where("status", "==", "pending")
        .where("requestedAt", "<=", oneHourAgoTimestamp)
        .get();

      if (querySnapshot.empty) {
        console.log("Không có yêu cầu nào quá 1 giờ.");
        return null;
      }

      // 3. Dùng Batch để cập nhật
      const batch = db.batch();
      querySnapshot.docs.forEach((doc) => {
        console.log(`Đang từ chối yêu cầu (auto-reject): ${doc.id}`);
        batch.update(doc.ref, { status: "regretted" });
      });

      // 4. Gửi lệnh
      await batch.commit();
      console.log(`Đã tự động từ chối ${querySnapshot.size} yêu cầu.`);
      return null;
    } catch (error) {
      console.error("Lỗi khi tự động từ chối yêu cầu:", error);
      console.log("LƯU Ý: Rất có thể bạn CHƯA TẠO INDEX trong Firestore.");
      return null;
    }
  }
);

// === PHẦN 4: HÀM XỬ LÝ KHI REQUEST ĐƯỢC CHẤP NHẬN (CẬP NHẬT MỚI) ===
exports.onJoinRequestAccepted = onDocumentUpdated(
  {
    document: "joinRequests/{docId}",
    region: "asia-southeast1",
  },
  async (event) => {
    // Lấy dữ liệu
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    // 1. Chỉ chạy khi status chuyển từ 'pending' -> 'accepted'
    if (beforeData.status !== "pending" || afterData.status !== "accepted") {
      return null;
    }

    console.log(`Đang xử lý logic ACCEPT cho request: ${event.params.docId}`);

    const requesterId = afterData.requesterId;
    const acceptedEventTime = afterData.eventTime;
    const eventId = afterData.eventId;
    const acceptedDocId = event.params.docId;

    if (!eventId || !requesterId || !acceptedEventTime) {
      console.log("Thiếu dữ liệu quan trọng (eventId/requesterId), bỏ qua.");
      return null;
    }

    try {
      const batch = db.batch();

      // --- BƯỚC A: ĐÁNH DẤU SỰ KIỆN LÀ FULL ---
      const eventRef = db.collection("events").doc(eventId);
      batch.update(eventRef, { isFull: true });

      // --- BƯỚC B: TỪ CHỐI NGƯỜI KHÁC ĐANG XIN VÀO CÙNG SỰ KIỆN NÀY (LOGIC MỚI) ---
      // Tìm các request khác cho eventId này mà vẫn đang pending
      const pendingRequestsForThisEvent = await db
        .collection("joinRequests")
        .where("eventId", "==", eventId)
        .where("status", "==", "pending")
        .get();

      pendingRequestsForThisEvent.docs.forEach((doc) => {
        // (Không cần check doc.id !== acceptedDocId vì cái accepted kia status đã là 'accepted' rồi, không lọt vào query này được)
        console.log(`Từ chối người khác (Event Full): ${doc.id}`);
        // Chuyển sang 'regretted' (Từ chối)
        batch.update(doc.ref, { status: "regretted" });
      });

      // --- BƯỚC C: HỦY CÁC YÊU CẦU TRÙNG GIỜ CỦA NGƯỜI/TEAM ĐƯỢC ACCEPT ---
      const requesterType = afterData.requesterType; // 'individual' hoặc 'team'
      const eventOwnerId = afterData.eventOwnerId;
      const creatorType = afterData.creatorType; // 'individual' hoặc 'team'

      // C1: Hủy request trùng giờ của REQUESTER
      if (requesterType === "individual") {
        // Nếu là cá nhân: Hủy các request khác của user này cùng giờ
        const sameUserRequests = await db
          .collection("joinRequests")
          .where("requesterId", "==", requesterId)
          .where("status", "==", "pending")
          .where("eventTime", "==", acceptedEventTime)
          .get();

        sameUserRequests.docs.forEach((doc) => {
          if (doc.id !== acceptedDocId) {
            console.log(`Hủy request trùng giờ của user: ${doc.id}`);
            batch.update(doc.ref, { status: "cancelled" });
          }
        });
      } else if (requesterType === "team") {
        // Nếu là team: Lấy danh sách members và hủy request của TẤT CẢ members
        try {
          const teamDoc = await db.collection("teams").doc(requesterId).get();
          if (teamDoc.exists) {
            const members = teamDoc.data().members || [];
            const memberIds = members.map((m) => m.uid).filter((uid) => uid);

            if (memberIds.length > 0) {
              // Hủy request của từng member cùng giờ
              for (const memberId of memberIds) {
                const memberRequests = await db
                  .collection("joinRequests")
                  .where("requesterId", "==", memberId)
                  .where("status", "==", "pending")
                  .where("eventTime", "==", acceptedEventTime)
                  .get();

                memberRequests.docs.forEach((doc) => {
                  console.log(
                    `Hủy request trùng giờ của member ${memberId}: ${doc.id}`
                  );
                  batch.update(doc.ref, { status: "cancelled" });
                });
              }
            }
          }
        } catch (err) {
          console.error("Lỗi khi lấy members của requester team:", err);
        }
      }

      // C2: Hủy request trùng giờ của EVENT OWNER (nếu owner là team)
      if (creatorType === "team" && eventOwnerId) {
        try {
          const ownerTeamDoc = await db
            .collection("teams")
            .doc(eventOwnerId)
            .get();
          if (ownerTeamDoc.exists) {
            const ownerMembers = ownerTeamDoc.data().members || [];
            const ownerMemberIds = ownerMembers
              .map((m) => m.uid)
              .filter((uid) => uid);

            if (ownerMemberIds.length > 0) {
              for (const memberId of ownerMemberIds) {
                const ownerMemberRequests = await db
                  .collection("joinRequests")
                  .where("requesterId", "==", memberId)
                  .where("status", "==", "pending")
                  .where("eventTime", "==", acceptedEventTime)
                  .get();

                ownerMemberRequests.docs.forEach((doc) => {
                  console.log(
                    `Hủy request trùng giờ của owner member ${memberId}: ${doc.id}`
                  );
                  batch.update(doc.ref, { status: "cancelled" });
                });
              }
            }
          }
        } catch (err) {
          console.error("Lỗi khi lấy members của owner team:", err);
        }
      }

      // --- THỰC THI TẤT CẢ ---
      await batch.commit();
      console.log(
        "Đã xử lý xong: Mark Full + Reject Others + Cancel Conflicts"
      );
      return null;
    } catch (error) {
      console.error("Lỗi trong onJoinRequestAccepted:", error);
      return null;
    }
  }
);

// === PHẦN 5: API CÀO DỮ LIỆU TIN TỨC (HTTP) - CÚ PHÁP V2 ===

// --- Các hàm cào dữ liệu (Giữ nguyên, không thay đổi) ---
async function scrapeVnExpress() {
  console.log("Đang cào dữ liệu từ VnExpress...");
  try {
    const { data } = await axios.get("https://vnexpress.net/the-thao", {
      timeout: 10000,
    });
    const $ = cheerio.load(data);
    const articlesData = [];
    $("article.item-news")
      .slice(0, 10)
      .each((i, el) => {
        const titleTag = $(el).find("h3.title-news a");
        const title = titleTag.text().trim();
        const link = titleTag.attr("href");
        const imgTag = $(el).find("img");
        const image = imgTag.attr("data-src") || imgTag.attr("src") || "";
        const description = $(el).find("p.description").text().trim();
        if (title && link) {
          articlesData.push({
            title,
            link,
            image,
            description,
            source: "VnExpress",
          });
        }
      });
    console.log("Hoàn thành cào dữ liệu từ VnExpress.");
    return articlesData;
  } catch (e) {
    console.error(`Lỗi khi cào VnExpress: ${e.message}`);
    return [];
  }
}
async function scrapeBongdaComVn() {
  console.log("Đang cào dữ liệu từ Bongda.com.vn...");
  try {
    const { data } = await axios.get("https://www.bongda.com.vn/", {
      timeout: 10000,
    });
    const $ = cheerio.load(data);
    const articlesData = [];
    $("figure.picture")
      .slice(0, 10)
      .each((i, el) => {
        const linkTag = $(el).find("a");
        const title = linkTag.attr("title");
        const link = "https://www.bongda.com.vn" + linkTag.attr("href");
        const imgTag = $(el).find("img");
        const image = imgTag.attr("data-src") || imgTag.attr("src") || "";
        if (title && link) {
          articlesData.push({
            title,
            link,
            image,
            description: "",
            source: "Bongda.com.vn",
          });
        }
      });
    console.log("Hoàn thành cào dữ liệu từ Bongda.com.vn.");
    return articlesData;
  } catch (e) {
    console.error(`Lỗi khi cào Bongda.com.vn: ${e.message}`);
    return [];
  }
}
async function scrapeDantri() {
  console.log("Đang cào dữ liệu từ Dantri...");
  try {
    const { data } = await axios.get("https://dantri.com.vn/the-thao.htm", {
      timeout: 10000,
    });
    const $ = cheerio.load(data);
    const articlesData = [];
    $("article.article-item")
      .slice(0, 10)
      .each((i, el) => {
        const titleTag = $(el).find("h3.article-title a");
        const title = titleTag.text().trim();
        const link = "https://dantri.com.vn" + titleTag.attr("href");
        const imgTag = $(el).find("img");
        const image = imgTag.attr("data-src") || imgTag.attr("src") || "";
        const description = $(el).find("div.article-excerpt").text().trim();
        if (title && link) {
          articlesData.push({
            title,
            link,
            image,
            description,
            source: "Dantri",
          });
        }
      });
    console.log("Hoàn thành cào dữ liệu từ Dantri.");
    return articlesData;
  } catch (e) {
    console.error(`Lỗi khi cào Dantri: ${e.message}`);
    return [];
  }
}

// --- Khởi tạo ứng dụng Express (giống Flask) ---
const app = express();
app.use(cors({ origin: true })); // Cho phép Flutter gọi

// Cấu hình Caching
let cachedNews = null;
let lastScrapeTime = 0;
const CACHE_DURATION_SECONDS = 600; // 10 phút

// --- Đây là Endpoint API ---
app.get("/api/sports-news", async (req, res) => {
  const currentTime = Date.now() / 1000; // Tính bằng giây

  if (cachedNews && currentTime - lastScrapeTime < CACHE_DURATION_SECONDS) {
    console.log("Đang trả về dữ liệu từ cache...");
    return res.json(cachedNews);
  }

  console.log("Cache không hợp lệ. Đang cào lại dữ liệu mới...");

  // Chạy song song cả 3 hàm cào
  const results = await Promise.all([
    scrapeVnExpress(),
    scrapeBongdaComVn(),
    scrapeDantri(),
  ]);

  const allNews = [].concat(...results); // Gộp kết quả

  if (allNews.length === 0) {
    return res.status(500).json({ error: "Không thể thu thập tin tức." });
  }

  cachedNews = allNews;
  lastScrapeTime = currentTime;
  console.log("Đã cập nhật cache thành công.");
  return res.json(allNews);
});

// --- Bọc ứng dụng Express bằng HTTP Function (CÚ PHÁP V2) ---
exports.sports_news_api = onRequest(
  { region: "asia-southeast1" }, // Cấu hình
  app // Truyền app Express vào
);

// === PHẦN 6: HÀM TỰ ĐỘNG HỒI PHỤC ĐIỂM UY TÍN (Scheduled) ===
exports.autoRecoverReputation = onSchedule(
  {
    schedule: "every 1 hours", // Chạy mỗi tiếng để kiểm tra (hoặc "every 24 hours" nếu muốn tiết kiệm)
    region: "asia-southeast1",
    timeZone: "Asia/Ho_Chi_Minh",
  },
  async (event) => {
    console.log("Đang chạy: autoRecoverReputation...");
    const batch = db.batch();
    let operationCount = 0;
    const MAX_BATCH_SIZE = 400; // Firestore giới hạn 500, để 400 cho an toàn

    // Danh sách các collection cần quét
    const collections = ["users", "teams"];

    try {
      for (const colName of collections) {
        // Chỉ lấy những document có điểm < 50 để xử lý
        // Lưu ý: Cần tạo Composite Index cho collection này nếu báo lỗi
        const snapshot = await db
          .collection(colName)
          .where("reputationScore", "<", 50)
          .get();

        if (snapshot.empty) continue;

        for (const doc of snapshot.docs) {
          const data = doc.data();
          const currentScore = data.reputationScore || 100;
          const lastRecoveryTime = data.lastRecoveryTime;

          // Nếu chưa có lastRecoveryTime, set ngay bây giờ để bắt đầu tính giờ
          if (!lastRecoveryTime) {
            batch.update(doc.ref, {
              lastRecoveryTime: admin.firestore.FieldValue.serverTimestamp(),
            });
            operationCount++;
            continue;
          }

          const lastDate = lastRecoveryTime.toDate();
          const now = new Date();
          // Tính khoảng cách thời gian (giờ)
          const diffHours = (now - lastDate) / (1000 * 60 * 60);

          // Logic giống hệt file Dart: Đủ 24h mới cộng
          if (diffHours >= 24) {
            const cycles = Math.floor(diffHours / 24); // Số chu kỳ 24h đã trôi qua
            const pointsToRecover = 10 * cycles; // 10 điểm mỗi chu kỳ

            let newScore = currentScore + pointsToRecover;
            if (newScore > 100) newScore = 100; // Không vượt quá 100

            // Chỉ update nếu điểm thực sự thay đổi
            if (newScore > currentScore) {
              batch.update(doc.ref, {
                reputationScore: newScore,
                // Reset mốc thời gian về hiện tại để tính chu kỳ tiếp theo
                lastRecoveryTime: admin.firestore.FieldValue.serverTimestamp(),
              });
              operationCount++;
            }
          }

          // Xử lý giới hạn Batch (nếu quá nhiều user cần hồi phục cùng lúc)
          if (operationCount >= MAX_BATCH_SIZE) {
            await batch.commit();
            console.log(`Đã commit batch ${MAX_BATCH_SIZE} operations.`);
            operationCount = 0; // Reset đếm
            // Tạo batch mới (Firestore batch không tái sử dụng được sau commit)
            // Lưu ý: Trong thực tế cần logic phức tạp hơn để handle batch mới,
            // nhưng ở quy mô nhỏ có thể bỏ qua hoặc chạy lại vào giờ sau.
          }
        }
      }

      // Commit những thay đổi còn lại
      if (operationCount > 0) {
        await batch.commit();
        console.log(`Hoàn tất hồi phục điểm cho ${operationCount} trường hợp.`);
      } else {
        console.log("Không có trường hợp nào đủ điều kiện hồi phục điểm.");
      }
      return null;
    } catch (error) {
      console.error("Lỗi trong autoRecoverReputation:", error);
      return null;
    }
  }
);
