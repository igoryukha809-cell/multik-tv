const STORAGE_KEY = "multikTvLocalChannelV1";
const ACTIVITY_POINTS = { quiz_complete: 1, drawing_saved: 1, story_read: 1, rhythm_complete: 1, idea_created: 1 };

function readStore() {
  try {
    const value = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    return {
      user: value.user || null,
      profile: value.profile || null,
      events: Array.isArray(value.events) ? value.events : [],
      ideas: Array.isArray(value.ideas) ? value.ideas : []
    };
  } catch {
    return { user: null, profile: null, events: [], ideas: [] };
  }
}
function writeStore(store) {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(store)); }
  catch { throw new Error("Локальное хранилище браузера недоступно или заполнено."); }
}
function makeId() {
  return globalThis.crypto?.randomUUID?.() || ("local-" + Date.now() + "-" + Math.random().toString(36).slice(2));
}

export async function ensureChannelUser() {
  const store = readStore();
  if (!store.user) {
    store.user = { id: makeId(), local: true };
    writeStore(store);
  }
  return store.user;
}

export async function getChannelProfile() {
  const user = await ensureChannelUser();
  const store = readStore();
  return { user, profile: store.profile };
}

export async function saveChannelProfile(nickname, avatar) {
  const user = await ensureChannelUser();
  const clean = String(nickname || "").trim();
  if (clean.length < 2 || clean.length > 20) throw new Error("Псевдоним должен содержать от 2 до 20 символов.");
  const store = readStore();
  store.profile = {
    user_id: user.id,
    nickname: clean,
    avatar: String(avatar || "🌟").slice(0, 8),
    created_at: store.profile?.created_at || new Date().toISOString(),
    updated_at: new Date().toISOString()
  };
  writeStore(store);
  return user;
}

export async function awardChannelActivity(activityCode) {
  if (!Object.hasOwn(ACTIVITY_POINTS, activityCode)) throw new Error("Неизвестный тип активности.");
  const user = await ensureChannelUser();
  const store = readStore();
  const today = new Date().toISOString().slice(0, 10);
  const duplicate = store.events.some(item => item.activity_code === activityCode && item.earned_on === today);
  if (duplicate) return { awarded: false, duplicate: true };
  store.events.push({
    id: makeId(),
    user_id: user.id,
    activity_code: activityCode,
    points: ACTIVITY_POINTS[activityCode],
    earned_on: today,
    created_at: new Date().toISOString()
  });
  writeStore(store);
  return { awarded: true, duplicate: false };
}

export async function getChannelPoints() {
  const user = await ensureChannelUser();
  const store = readStore();
  const events = [...store.events].sort((a, b) => b.created_at.localeCompare(a.created_at));
  return { user, events, total: events.reduce((sum, item) => sum + Number(item.points || 0), 0) };
}

export async function submitChannelIdea({ title, description, category = "idea" }) {
  const user = await ensureChannelUser();
  const cleanTitle = String(title || "").trim();
  const cleanDescription = String(description || "").trim();
  if (cleanTitle.length < 3 || cleanTitle.length > 60) throw new Error("Название должно содержать от 3 до 60 символов.");
  if (cleanDescription.length > 500) throw new Error("Описание слишком длинное.");
  const store = readStore();
  const idea = {
    id: makeId(),
    user_id: user.id,
    title: cleanTitle,
    description: cleanDescription,
    category,
    review_status: "local_draft",
    created_at: new Date().toISOString()
  };
  store.ideas.push(idea);
  writeStore(store);
  return idea;
}

export function getChannelIdeas() {
  return [...readStore().ideas].sort((a, b) => b.created_at.localeCompare(a.created_at));
}
