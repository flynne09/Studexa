const { onObjectFinalized } = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");
const os = require("os");

const pdfParse = require("pdf-parse");
const mammoth = require("mammoth");
const officeParser = require("officeparser");

admin.initializeApp();

/**
 * Helper to parse PPTX files using officeparser safely.
 */
async function parsePptx(filePathOrBuffer) {
  if (typeof officeParser.parseOfficeAsync === "function") {
    return await officeParser.parseOfficeAsync(filePathOrBuffer);
  }
  return new Promise((resolve, reject) => {
    try {
      const res = officeParser.parseOffice(filePathOrBuffer, (data, err) => {
        if (err) return reject(err);
        resolve(data);
      });
      if (res && typeof res.then === "function") {
        res.then(resolve).catch(reject);
      }
    } catch (e) {
      reject(e);
    }
  });
}

/**
 * Storage-triggered Cloud Function (2nd gen) that triggers on upload to
 * uploads/{teacherId}/{materialId}/{filename}.
 * Extracts text from PDF, DOCX, and PPTX files and updates Firestore materials/{materialId}.
 */
exports.extractText = onObjectFinalized(
  {
    cpu: 1,
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async (event) => {
    const fileObject = event.data;
    const filePath = fileObject.name; // e.g. uploads/teacher123/mat456/notes.pdf

    if (!filePath) {
      console.log("No file path found in event.");
      return;
    }

    // Path pattern: uploads/{teacherId}/{materialId}/{filename}
    const pathSegments = filePath.split("/");
    if (pathSegments.length < 4 || pathSegments[0] !== "uploads") {
      console.log(`Ignoring file outside 'uploads/{teacherId}/{materialId}/': ${filePath}`);
      return;
    }

    const teacherId = pathSegments[1];
    const materialId = pathSegments[2];
    const fileName = pathSegments.slice(3).join("/");
    const extension = path.extname(fileName).toLowerCase().replace(".", "");

    console.log(`Processing file: ${fileName} (materialId: ${materialId}, teacherId: ${teacherId})`);

    const firestore = admin.firestore();
    const materialRef = firestore.collection("materials").doc(materialId);

    // Map extension to supported fileType: "pdf" | "pptx" | "docx"
    let fileType = null;
    if (extension === "pdf") {
      fileType = "pdf";
    } else if (extension === "docx") {
      fileType = "docx";
    } else if (extension === "pptx") {
      fileType = "pptx";
    }

    // Check for unsupported format
    if (!fileType) {
      console.warn(`Unsupported file format '${extension}' for ${filePath}`);
      await materialRef.set(
        {
          status: "failed",
          errorReason: "unsupported_format",
          fileRef: filePath,
          fileType: extension || "unknown",
        },
        { merge: true }
      );
      return;
    }

    const bucket = admin.storage().bucket(fileObject.bucket);
    const tempFilePath = path.join(os.tmpdir(), `${materialId}_${path.basename(fileName)}`);

    try {
      // Download the file from Firebase Storage to Cloud Function /tmp
      await bucket.file(filePath).download({ destination: tempFilePath });
      const fileBuffer = fs.readFileSync(tempFilePath);

      let rawExtractedText = "";

      // Route to matching extraction library
      if (fileType === "pdf") {
        const parsed = await pdfParse(fileBuffer);
        rawExtractedText = parsed.text || "";
      } else if (fileType === "docx") {
        const parsed = await mammoth.extractRawText({ buffer: fileBuffer });
        rawExtractedText = parsed.value || "";
      } else if (fileType === "pptx") {
        rawExtractedText = await parsePptx(tempFilePath);
      }

      const trimmedText = (rawExtractedText || "").trim();

      // Validate non-trivial content (not empty or near-empty)
      if (trimmedText.length < 20) {
        console.warn(`No extractable text found in file ${filePath} (length: ${trimmedText.length})`);
        await materialRef.set(
          {
            status: "failed",
            errorReason: "no_extractable_text",
            fileRef: filePath,
            fileType: fileType,
          },
          { merge: true }
        );
        return;
      }

      // Success: write status "ready", extractedText, and extractedAt
      await materialRef.set(
        {
          status: "ready",
          extractedText: trimmedText,
          extractedAt: admin.firestore.FieldValue.serverTimestamp(),
          fileRef: filePath,
          fileType: fileType,
        },
        { merge: true }
      );

      console.log(`Successfully extracted ${trimmedText.length} characters for materialId: ${materialId}`);
    } catch (parseError) {
      console.error(`Parse error encountered while processing ${filePath}:`, parseError);
      await materialRef.set(
        {
          status: "failed",
          errorReason: "parse_error",
          fileRef: filePath,
          fileType: fileType,
        },
        { merge: true }
      );
    } finally {
      // Clean up temporary file
      if (fs.existsSync(tempFilePath)) {
        try {
          fs.unlinkSync(tempFilePath);
        } catch (cleanupErr) {
          console.warn(`Failed to remove temp file ${tempFilePath}:`, cleanupErr);
        }
      }
    }
  }
);
