export interface User {
  id: string;
  uri: string;
  displayName: string;
  email: string;
  role: 'admin' | 'moderator' | 'member' | 'guest';
  avatar: string;
  roleColor?: string;
  roleTitle?: string;
}

export interface Category {
  id: string;
  uri: string;
  slug: string;
  name: string;
  description: string;
  position: number;
  visibility: 'public' | 'members-only' | 'role-restricted';
  color: string;
  iconName: string;
}

export interface Commit {
  id: string;
  position: number;
  text: string;
  createdAt: string;
}

export interface MessageVersion {
  id: string;
  bodyMd: string;
  createdAt: string;
}

export interface Message {
  id: string;
  uri: string;
  topicId: string;
  author: User;
  replyToId?: string;
  replyToAuthor?: string;
  replyToSnippet?: string;
  state: 'open' | 'closed';
  openedAt: number; // timestamp ms
  closesAt: number; // timestamp ms
  closedAt?: number;
  commits: Commit[];
  bodyMd: string;
  edited?: boolean;
  versions?: MessageVersion[];
}

export interface Topic {
  id: string;
  uri: string;
  categoryId: string;
  author: User;
  title: string;
  slug: string;
  state: 'open' | 'locked';
  pinned: boolean;
  forkedFromMessageId?: string;
  forkedFromTopicTitle?: string;
  createdAt: string;
  lastActivityAt: string;
  messageCount: number;
  unreadCount?: number;
}

export interface NotificationItem {
  id: string;
  userId: string;
  kind: 'mention' | 'reply';
  messageId: string;
  topicId: string;
  topicTitle: string;
  actor: User;
  snippet: string;
  readAt?: string;
  createdAt: string;
}

export interface ModAction {
  id: string;
  moderator: User;
  action: 'lock_topic' | 'close_message' | 'delete_message' | 'ban_user' | 'pin_topic';
  targetType: 'topic' | 'message' | 'user';
  targetId: string;
  targetDescription: string;
  reason: string;
  createdAt: string;
}

export interface AppSettings {
  serverName: string;
  gmWindowSeconds: number; // default 45s
  registrationMode: 'open' | 'invite-only';
  smtpConfigured: boolean;
  allowGuestReading: boolean;
}
