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

      // --- BƯỚC C: HỦY CÁC YÊU CẦU TRÙNG GIỜ CỦA CHÍNH NGƯỜI ĐƯỢC ACCEPT ---
      // Tìm các request của user này ở event khác nhưng cùng khung giờ
      const sameUserOtherRequests = await db
        .collection("joinRequests")
        .where("requesterId", "==", requesterId)
        .where("status", "==", "pending")
        .where("eventTime", "==", acceptedEventTime)
        .get();

      sameUserOtherRequests.docs.forEach((doc) => {
        if (doc.id !== acceptedDocId) {
          console.log(`Hủy request trùng giờ của user: ${doc.id}`);
          // Chuyển sang 'cancelled' (Hủy bỏ do user đã bận event này)
          batch.update(doc.ref, { status: "cancelled" });
        }
      });

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
