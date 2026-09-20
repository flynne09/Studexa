// Keep these exclusions aligned with the legacy Firebase generator.
export function isTableHeaderQuestion(q) {
  if (!q) return false;
  const prompt = (q.question || "").toLowerCase().trim();
  const answer = (q.correctAnswer || "").toLowerCase().trim().replace(/^[a-d]\.\s*/, "");
  if (/\b(in\s+(?:the\s+)?(?:table|column|row)|which\s+column|what\s+is\s+(?:the\s+)?(?:header|column|attribute)|listed\s+in\s+column|under\s+column|title\s+of\s+column)\b/i.test(prompt)) return true;
  if (/\b(?:column|header|col|row)\s+[a-z0-9]+\b/i.test(prompt) &&
      (prompt.includes("what") || prompt.includes("which") || prompt.includes("identify"))) return true;
  return /^(?:column\s+[a-z0-9]+|header\s+[a-z0-9]+|row\s+[a-z0-9]+|col\s+[a-z0-9]+|attribute|attributes|value|values|field|fields|no\.?|num\.?|number|description|remarks|category|type)$/i.test(answer);
}

export function isFillerOrBoilerplateQuestion(q) {
  if (!q) return false;
  const prompt = (q.question || "").toLowerCase().trim();
  const answer = (q.correctAnswer || "").toLowerCase().trim().replace(/^[a-d]\.\s*/, "");
  const fillerPromptPattern = /(?:\b(?:copyright|all\s+rights\s+reserved|creative\s+commons|licensed\s+under|authors?|written\s+by|who\s+is\s+the\s+author|who\s+is\s+the\s+instructor|who\s+is\s+the\s+professor|instructors?|emails?|office\s+hours|syllabus|grading\s+policy|course\s+code|prerequisite|homework\s+assignment|due\s+date|welcome\s+to|in\s+this\s+lecture|today\x27s\s+lecture|previous\s+slide|next\s+slide|thank\s+you\s+for\s+(?:listening|attending)|summary\s+of\s+today|slide\s+\d+|page\s+\d+|figure\s+\d+|table\s+\d+|chapter\s+\d+|\d+(?:st|nd|rd|th)?\s+edition|edition|references|acknowledgments?)\b|any\s+questions\?)/i;
  if (fillerPromptPattern.test(prompt)) return true;
  if (/\b(?:on slide|in chapter|on page|published in|publication date|file name)\b/i.test(prompt)) return true;
  const fillerAnswerPattern = /^(?:all rights reserved|copyright|creative commons|welcome|thank you|any questions|dr\.\s+\w+|prof\.\s+\w+|professor|instructor|syllabus|office hours|slide\s+\d+|page\s+\d+|chapter\s+\d+|https?:\/\/\S+|www\.\S+|\S+@\S+)$/i;
  return fillerAnswerPattern.test(answer) || answer.includes("@") || answer.includes("http://") ||
    answer.includes("https://") || answer.includes("www.");
}
