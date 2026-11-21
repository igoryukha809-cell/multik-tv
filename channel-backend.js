import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.119.2/+esm";

const SUPABASE_URL = "https://hryyvwzkyxhmpmvvdqqx.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_1T92JRiGk-R2t3OmiQkCkA_TgrA6MUi";

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

export async function ensureChannelUser() {
  const { data: current, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) throw sessionError;
  if (current.session?.user) return current.session.user;
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw error;
  if (!data.user) throw new Error("Не удалось создать гостевую сессию.");
  return data.user;
}

export async function getChannelProfile() {
  const user = await ensureChannelUser();
  const { data, error } = await supabase.from("channel_profiles").select("user_id,nickname,avatar,created_at").eq("user_id", user.id).maybeSingle();
  if (error) throw error;
  return { user, profile: data };
}

export async function saveChannelProfile(nickname, avatar) {
  const user = await ensureChannelUser();
  const clean = String(nickname || "").trim();
  if (clean.length < 2 || clean.length > 20) throw new Error("Псевдоним должен содержать от 2 до 20 символов.");
  const { data: old, error: readError } = await supabase.from("channel_profiles").select("user_id").eq("user_id", user.id).maybeSingle();
  if (readError) throw readError;
  const result = old
    ? await supabase.from("channel_profiles").update({ nickname: clean, avatar }).eq("user_id", user.id)
    : await supabase.from("channel_profiles").insert({ user_id: user.id, nickname: clean, avatar });
  if (result.error) throw result.error;
  return user;
}

export async function awardChannelActivity(activityCode) {
  const user = await ensureChannelUser();
  const { error } = await supabase.from("channel_point_events").insert({ user_id: user.id, activity_code: activityCode });
  if (error?.code === "23505") return { awarded: false, duplicate: true };
  if (error) throw error;
  return { awarded: true, duplicate: false };
}

export async function getChannelPoints() {
  const user = await ensureChannelUser();
  const { data, error } = await supabase.from("channel_point_events").select("points,activity_code,earned_on,created_at").eq("user_id", user.id).order("created_at", { ascending: false });
  if (error) throw error;
  return { user, events: data || [], total: (data || []).reduce((sum, item) => sum + Number(item.points || 0), 0) };
}

export async function submitChannelIdea({ title, description, category = "idea" }) {
  const user = await ensureChannelUser();
  const { data, error } = await supabase.from("channel_contest_submissions").insert({
    user_id: user.id,
    title: String(title || "").trim(),
    description: String(description || "").trim(),
    category
  }).select("id,title,review_status,created_at").single();
  if (error) throw error;
  return data;
}
