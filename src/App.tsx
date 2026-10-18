import React, { useState } from 'react';
import { 
  User, 
  Category, 
  Topic, 
  Message, 
  NotificationItem, 
  ModAction, 
  AppSettings 
} from './types';
import { 
  CURRENT_USER, 
  INITIAL_CATEGORIES, 
  INITIAL_TOPICS, 
  INITIAL_MESSAGES, 
  INITIAL_NOTIFICATIONS, 
  INITIAL_MOD_ACTIONS, 
  INITIAL_SETTINGS 
} from './data/mockData';
import { Header } from './components/Header';
import { ForumHome } from './components/ForumHome';
import { CategoryView } from './components/CategoryView';
import { TopicView } from './components/TopicView';
import { NewTopicModal } from './components/NewTopicModal';
import { SearchModal } from './components/SearchModal';
import { NotificationsModal } from './components/NotificationsModal';
import { AdminSettingsModal } from './components/AdminSettingsModal';
import { PhoenixStarterView } from './components/PhoenixStarterView';
import { ComposerPrototypeView } from './components/ComposerPrototypeView';

export const App: React.FC = () => {
  // Primary application state
  const [currentUser] = useState<User>(CURRENT_USER);
  const [settings, setSettings] = useState<AppSettings>(INITIAL_SETTINGS);
  const [categories, setCategories] = useState<Category[]>(INITIAL_CATEGORIES);
  const [topics, setTopics] = useState<Topic[]>(INITIAL_TOPICS);
  const [messages, setMessages] = useState<Message[]>(INITIAL_MESSAGES);
  const [notifications, setNotifications] = useState<NotificationItem[]>(INITIAL_NOTIFICATIONS);
  const [modActions, setModActions] = useState<ModAction[]>(INITIAL_MOD_ACTIONS);

  // Navigation state
  const [activeView, setActiveView] = useState<'forum' | 'prototype' | 'phoenix'>('forum');
  const [selectedCategory, setSelectedCategory] = useState<Category | null>(null);
  const [selectedTopic, setSelectedTopic] = useState<Topic | null>(null);

  // Modal states
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [isNotificationsOpen, setIsNotificationsOpen] = useState(false);
  const [isAdminOpen, setIsAdminOpen] = useState(false);
  const [isNewTopicOpen, setIsNewTopicOpen] = useState(false);
  const [newTopicCategoryPrefill, setNewTopicCategoryPrefill] = useState<string | undefined>(undefined);
  const [forkSourceMessage, setForkSourceMessage] = useState<Message | null>(null);
  const [forkSourceTopic, setForkSourceTopic] = useState<Topic | null>(null);

  // --- Growing Message Engine Actions (GM-01 to GM-12: Composer is the open message) ---

  // GM-01: Enter with no open message posts a new message, open and visible to readers at once
  const handleStartNewMessage = (text: string, closed = false) => {
    if (!selectedTopic) return;
    const now = Date.now();
    const windowDurationMs = (settings.gmWindowSeconds || 45) * 1000;

    const newMessage: Message = {
      id: `msg_${Date.now()}`,
      uri: `idejo://messages/${Date.now()}`,
      topicId: selectedTopic.id,
      author: currentUser,
      state: closed ? 'closed' : 'open',
      openedAt: now,
      closesAt: closed ? now : now + windowDurationMs, // Marks when author may start a new message (GM-03, GM-04)
      closedAt: closed ? now : undefined,
      commits: [
        {
          id: `com_${Date.now()}_1`,
          position: 1,
          text,
          createdAt: 'Just now',
        },
      ],
      bodyMd: text,
    };

    setMessages((prev) => [...prev, newMessage]);

    // Update topic stats
    setTopics((prev) =>
      prev.map((t) =>
        t.id === selectedTopic.id
          ? {
              ...t,
              messageCount: t.messageCount + 1,
              lastActivityAt: 'Just now',
            }
          : t
      )
    );
  };

  // GM-02: Enter while author has open message sends unsent changes as a new commit; text stays in composer
  const handleCommitChanges = (newText: string) => {
    if (!selectedTopic) return;

    setMessages((prev) =>
      prev.map((msg) => {
        if (
          msg.topicId === selectedTopic.id &&
          msg.state === 'open' &&
          msg.author.id === currentUser.id
        ) {
          const nextPosition = msg.commits.length + 1;
          const separator = newText.startsWith('\n') ? '' : (msg.bodyMd.endsWith('\n') ? '' : ' ');
          const updatedBody = newText.startsWith(msg.bodyMd)
            ? newText.trim()
            : `${msg.bodyMd}${separator}${newText.trim()}`;
          const commitText = newText.startsWith(msg.bodyMd)
            ? (newText.slice(msg.bodyMd.length).trim() || newText.trim())
            : newText.trim();

          const newCommit = {
            id: `com_${Date.now()}_${nextPosition}`,
            position: nextPosition,
            text: commitText,
            createdAt: 'Just now',
          };

          return {
            ...msg,
            commits: [...msg.commits, newCommit],
            bodyMd: updatedBody,
            // GM-03: closesAt is NEVER extended by appends!
          };
        }
        return msg;
      })
    );
  };

  // GM-04, GM-05: Close active open message
  const handleCloseOpenMessage = (messageId?: string) => {
    const now = Date.now();
    setMessages((prev) =>
      prev.map((msg) => {
        if (messageId ? msg.id === messageId : (msg.state === 'open' && msg.author.id === currentUser.id)) {
          return {
            ...msg,
            state: 'closed' as const,
            closedAt: now,
          };
        }
        return msg;
      })
    );
  };

  // GM-05: After window ends, Ctrl+Enter closes current message and starts a new one
  const handleCloseOpenMessageAndStartNew = (newText: string) => {
    handleCloseOpenMessage();
    handleStartNewMessage(newText);
  };

  // Create new topic (TP-01, TP-02, GM-14: first message posted closed)
  const handleCreateTopic = (title: string, categoryId: string, firstMessageBody: string) => {
    const now = Date.now();
    const newTopicId = `top_${Date.now()}`;
    const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

    const newTopic: Topic = {
      id: newTopicId,
      uri: `idejo://topics/${slug}`,
      categoryId,
      author: currentUser,
      title,
      slug,
      state: 'open',
      pinned: false,
      forkedFromMessageId: forkSourceMessage?.id,
      forkedFromTopicTitle: forkSourceTopic?.title,
      createdAt: new Date().toISOString(),
      lastActivityAt: 'Just now',
      messageCount: 1,
    };

    // GM-14: The first message of a topic is never open
    const firstMsg: Message = {
      id: `msg_${Date.now()}_first`,
      uri: `idejo://messages/${Date.now()}_first`,
      topicId: newTopicId,
      author: currentUser,
      state: 'closed',
      openedAt: now,
      closesAt: now,
      closedAt: now,
      commits: [
        {
          id: `com_${Date.now()}_1`,
          position: 1,
          text: firstMessageBody,
          createdAt: 'Just now',
        },
      ],
      bodyMd: firstMessageBody,
    };

    setTopics((prev) => [newTopic, ...prev]);
    setMessages((prev) => [...prev, firstMsg]);

    const cat = categories.find((c) => c.id === categoryId) || categories[0];
    setSelectedCategory(cat);
    setSelectedTopic(newTopic);
    setForkSourceMessage(null);
    setForkSourceTopic(null);
  };

  // TP-09: Fork a message into a new topic
  const handleForkToNewTopic = (sourceMessage: Message, sourceTopic: Topic) => {
    setForkSourceMessage(sourceMessage);
    setForkSourceTopic(sourceTopic);
    setNewTopicCategoryPrefill(sourceTopic.categoryId);
    setIsNewTopicOpen(true);
  };

  // Moderator actions (MO-02, GM-12: open message closes on topic lock)
  const handleToggleLock = (topicId: string) => {
    setTopics((prev) =>
      prev.map((t) => {
        if (t.id === topicId) {
          const nextState = t.state === 'locked' ? 'open' : 'locked';
          if (nextState === 'locked') {
            // GM-12: An open message also closes when its topic is locked
            setMessages((msgs) =>
              msgs.map((m) =>
                m.topicId === topicId && m.state === 'open'
                  ? { ...m, state: 'closed' as const, closedAt: Date.now() }
                  : m
              )
            );
          }
          setModActions((acts) => [
            {
              id: `mod_${Date.now()}`,
              moderator: currentUser,
              action: 'lock_topic',
              targetType: 'topic',
              targetId: topicId,
              targetDescription: t.title,
              reason: nextState === 'locked' ? 'Moderator locked topic' : 'Moderator unlocked topic',
              createdAt: 'Just now',
            },
            ...acts,
          ]);
          return { ...t, state: nextState };
        }
        return t;
      })
    );
  };

  const handleTogglePin = (topicId: string) => {
    setTopics((prev) =>
      prev.map((t) => {
        if (t.id === topicId) {
          const nextPinned = !t.pinned;
          setModActions((acts) => [
            {
              id: `mod_${Date.now()}`,
              moderator: currentUser,
              action: 'pin_topic',
              targetType: 'topic',
              targetId: topicId,
              targetDescription: t.title,
              reason: nextPinned ? 'Moderator pinned topic to top' : 'Moderator unpinned topic',
              createdAt: 'Just now',
            },
            ...acts,
          ]);
          return { ...t, pinned: nextPinned };
        }
        return t;
      })
    );
  };

  const handleMoveCategory = (topicId: string, newCategoryId: string) => {
    setTopics((prev) =>
      prev.map((t) => (t.id === topicId ? { ...t, categoryId: newCategoryId } : t))
    );
    const targetCat = categories.find((c) => c.id === newCategoryId);
    if (targetCat) {
      setSelectedCategory(targetCat);
    }
  };

  const handleDeleteMessage = (messageId: string) => {
    if (!window.confirm("Are you sure you want to delete this message?")) return;
    setMessages((prev) => prev.filter((m) => m.id !== messageId));
  };

  return (
    <div className="min-h-screen flex flex-col bg-stone-50 dark:bg-stone-950 text-stone-900 dark:text-stone-100 transition-colors">
      {/* Top Application Header */}
      <Header
        currentUser={currentUser}
        settings={settings}
        notifications={notifications}
        activeView={activeView}
        onChangeView={setActiveView}
        onNavigateHome={() => {
          setSelectedTopic(null);
          setSelectedCategory(null);
        }}
        onOpenSearch={() => setIsSearchOpen(true)}
        onOpenNotifications={() => setIsNotificationsOpen(true)}
        onOpenAdmin={() => setIsAdminOpen(true)}
        onOpenNewTopic={() => {
          setForkSourceMessage(null);
          setForkSourceTopic(null);
          setNewTopicCategoryPrefill(selectedCategory?.id);
          setIsNewTopicOpen(true);
        }}
      />

      {/* Main View Router */}
      <main className="flex-1">
        {activeView === 'phoenix' ? (
          <PhoenixStarterView onReturnToForum={() => setActiveView('forum')} />
        ) : activeView === 'prototype' ? (
          <ComposerPrototypeView currentUser={currentUser} />
        ) : selectedTopic ? (
          <TopicView
            topic={selectedTopic}
            category={
              categories.find((c) => c.id === selectedTopic.categoryId) || categories[0]
            }
            categories={categories}
            messages={messages.filter((m) => m.topicId === selectedTopic.id)}
            currentUser={currentUser}
            windowDurationSeconds={settings.gmWindowSeconds}
            onBack={() => {
              setSelectedTopic(null);
            }}
            onStartNewMessage={handleStartNewMessage}
            onCommitChanges={handleCommitChanges}
            onCloseOpenMessage={handleCloseOpenMessage}
            onCloseOpenMessageAndStartNew={handleCloseOpenMessageAndStartNew}
            onToggleLock={handleToggleLock}
            onTogglePin={handleTogglePin}
            onMoveCategory={handleMoveCategory}
            onDeleteMessage={handleDeleteMessage}
            onForceCloseMessage={handleCloseOpenMessage}
            onForkToNewTopic={handleForkToNewTopic}
          />
        ) : selectedCategory ? (
          <CategoryView
            category={selectedCategory}
            topics={topics}
            onSelectTopic={(topic) => setSelectedTopic(topic)}
            onNewTopic={(catId) => {
              setForkSourceMessage(null);
              setForkSourceTopic(null);
              setNewTopicCategoryPrefill(catId);
              setIsNewTopicOpen(true);
            }}
            onBackToHome={() => setSelectedCategory(null)}
          />
        ) : (
          <ForumHome
            categories={categories}
            topics={topics}
            settings={settings}
            onSelectCategory={(category) => setSelectedCategory(category)}
            onSelectTopic={(topic) => {
              const cat = categories.find((c) => c.id === topic.categoryId);
              if (cat) setSelectedCategory(cat);
              setSelectedTopic(topic);
            }}
            onNewTopic={() => {
              setForkSourceMessage(null);
              setForkSourceTopic(null);
              setIsNewTopicOpen(true);
            }}
          />
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-stone-200 dark:border-stone-800/80 bg-white dark:bg-stone-900/60 py-6 text-xs text-stone-500">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 flex flex-col sm:flex-row items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <span className="font-bold text-stone-800 dark:text-stone-200">Idejo</span>
            <span>&bull;</span>
            <span>AGPL-3.0 License</span>
            <span>&bull;</span>
            <span>v0.1 Pilot Edition (GM-02 to GM-12 in place)</span>
          </div>

          <div className="flex items-center gap-4">
            <button
              onClick={() => setIsAdminOpen(true)}
              className="hover:text-stone-800 dark:hover:text-stone-200 transition-colors"
            >
              Server Settings
            </button>
            <button
              onClick={() => setActiveView(activeView === 'forum' ? 'phoenix' : 'forum')}
              className="hover:text-stone-800 dark:hover:text-stone-200 transition-colors text-orange-600 dark:text-orange-400 font-medium"
            >
              {activeView === 'forum' ? 'View M0 Foundations' : 'View Community Forum'}
            </button>
          </div>
        </div>
      </footer>

      {/* Modals */}
      {isNewTopicOpen && (
        <NewTopicModal
          categories={categories}
          prefillCategoryId={newTopicCategoryPrefill}
          forkFromMessage={forkSourceMessage}
          forkFromTopic={forkSourceTopic}
          onClose={() => {
            setIsNewTopicOpen(false);
            setForkSourceMessage(null);
            setForkSourceTopic(null);
          }}
          onCreateTopic={handleCreateTopic}
        />
      )}

      {isSearchOpen && (
        <SearchModal
          topics={topics}
          messages={messages}
          categories={categories}
          onClose={() => setIsSearchOpen(false)}
          onSelectTopic={(topic) => {
            const cat = categories.find((c) => c.id === topic.categoryId);
            if (cat) setSelectedCategory(cat);
            setSelectedTopic(topic);
          }}
        />
      )}

      {isNotificationsOpen && (
        <NotificationsModal
          notifications={notifications}
          topics={topics}
          onClose={() => setIsNotificationsOpen(false)}
          onSelectTopic={(topic) => {
            const cat = categories.find((c) => c.id === topic.categoryId);
            if (cat) setSelectedCategory(cat);
            setSelectedTopic(topic);
          }}
          onMarkAllAsRead={() => {
            setNotifications((prev) =>
              prev.map((n) => ({ ...n, readAt: new Date().toISOString() }))
            );
          }}
        />
      )}

      {isAdminOpen && (
        <AdminSettingsModal
          settings={settings}
          categories={categories}
          modActions={modActions}
          currentUser={currentUser}
          onClose={() => setIsAdminOpen(false)}
          onUpdateSettings={(newSet) => setSettings((s) => ({ ...s, ...newSet }))}
          onCreateCategory={(newCat) => {
            const cat: Category = {
              ...newCat,
              id: `cat_${Date.now()}`,
              uri: `idejo://categories/${newCat.slug}`,
            };
            setCategories((prev) => [...prev, cat]);
          }}
        />
      )}
    </div>
  );
};

export default App;
