# בדיקת אפליקציית האייפון בלי Mac אישי

התיקייה הזו היא שורש מאגר iOS עצמאי: `ScreenMind.xcodeproj`, קוד האפליקציה, הרחבת השיתוף, בדיקות ותהליך GitHub Actions. אין צורך להעלות את אתר Next.js, מאגרי נתונים או מפתחות.

## מה התהליך עושה

בהפעלה ידנית הוא משתמש ב־`macos-15`, בוחר סימולטור iPhone זמין עם iOS 17 ומעלה ומריץ `xcodebuild test`. הבדיקות יוצרות נתוני דמה בלבד. בסיום נשמרים יומן בנייה ותוצאות XCTest למשך שבעה ימים. אין דרישה לתעודות Apple בשלב הסימולטור.

התהליך מוגבל ל־25 דקות ולריצה אחת בכל ענף. הוא אינו מופעל מעצם העלאת הקוד.

## איך מפעילים

1. יוצרים מאגר GitHub פרטי עבור קוד האייפון.
2. מעלים את תוכן התיקייה הזו לשורש המאגר, כולל `.github/workflows/ios-simulator.yml`. אם מעלים את כל פרויקט האתר, צריך לשנות את נתיבי ה־workflow — החבילה הזו נועדה למאגר iOS עצמאי.
3. בודקים את מכסת GitHub Actions והגבלת ההוצאות בחשבון. דקות Mac במאגר פרטי יכולות להיות מחויבות לאחר ניצול המכסה הכלולה.
4. נכנסים ל־Actions → ScreenMind iPhone build and tests → Run workflow.
5. אחרי הריצה בודקים שהסטטוס ירוק ומורידים את ScreenMind-iOS-verification. אם נכשל, משתמשים ב־build-and-test.log לתיקון, בלי להכריז שהאפליקציה נבנתה.

## מה זה עדיין לא נותן

תוצאה ירוקה היא קומפילציה ובדיקות סימולטור, לא קובץ להתקנה באייפון. התקנה במכשיר דורשת חתימה ופרופיל מתאים; TestFlight דורש את מסלול Apple Developer/App Store Connect. יש להשלים בדיקת Photos, Files, שיתוף ופינוי על מכשיר אמיתי.

## מצב מקומי

ה־workflow הוכן, אבל לא הורץ בענן. חשבון GitHub מחובר דרך המחבר; לא נמצא בו מאגר ScreenMind בחיפוש. הכניסה המקומית של GitHub CLI לחשבון DavidPatlas-AI מדווחת על אישור לא תקף, ולכן לא בוצעו יצירת מאגר או העלאת קוד.

## מקורות רשמיים שנבדקו ב־27.10.2026

- [שרתי GitHub לבנייה ומכסות](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- [checkout](https://github.com/actions/checkout) ו־[upload-artifact](https://github.com/actions/upload-artifact)
- [חתימה והפצה למכשירים של Apple](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
