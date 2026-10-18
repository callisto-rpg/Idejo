import React from 'react';
import { 
  PlusCircle, 
  Sparkles, 
  MessageSquare, 
  Clock, 
  ArrowRight, 
  Users, 
  ShieldCheck, 
  Pin,
  Flame,
  HelpCircle
} from 'lucide-react';
import { Category, Topic, AppSettings } from '../types';

interface ForumHomeProps {
  categories: Category[];
  topics: Topic[];
  settings: AppSettings;
  onSelectCategory: (category: Category) => void;
  onSelectTopic: (topic: Topic) => void;
  onNewTopic: () => void;
}

export const ForumHome: React.FC<ForumHomeProps> = ({
  categories,
  topics,
  settings,
  onSelectCategory,
  onSelectTopic,
  onNewTopic,
}) => {
  // Pinned or recent topics across server
  const featuredTopics = topics.slice(0, 4);

  return (
    <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8 space-y-10">
      {/* Hero Banner explaining Idejo's Core Innovation */}
      <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-stone-900 via-stone-900 to-stone-950 text-white p-6 sm:p-10 border border-stone-800 shadow-xl">
        <div className="relative z-10 max-w-2xl space-y-4">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-orange-500/20 text-orange-400 text-xs font-semibold border border-orange-500/30">
            <Sparkles className="w-3.5 h-3.5" />
            <span>Idejo v0.1 Pilot &bull; Live Growing Messages</span>
          </div>

          <h1 className="text-2xl sm:text-4xl font-bold tracking-tight font-serif leading-tight">
            Conversations that feel like live chat, but read like an organized forum.
          </h1>

          <p className="text-stone-300 text-sm sm:text-base leading-relaxed">
            In Idejo, quick lines sent with <kbd className="px-1.5 py-0.5 bg-stone-800 rounded text-stone-200 border border-stone-700 text-xs font-mono">Enter</kbd> merge into one open message for a fixed <strong className="text-orange-400">{settings.gmWindowSeconds}-second window</strong>. No message sprawl, no disjointed fragments.
          </p>

          <div className="flex flex-wrap items-center gap-3 pt-2">
            <button
              onClick={onNewTopic}
              className="px-5 py-2.5 bg-orange-600 hover:bg-orange-700 active:bg-orange-800 text-white text-sm font-semibold rounded-xl shadow-lg shadow-orange-600/30 transition-all flex items-center gap-2 hover:scale-[1.02]"
            >
              <PlusCircle className="w-4 h-4" />
              <span>Start a New Topic</span>
            </button>

            <button
              onClick={() => {
                const pilotCat = categories.find(c => c.slug === 'gm-pilot') || categories[0];
                onSelectCategory(pilotCat);
              }}
              className="px-5 py-2.5 bg-stone-800 hover:bg-stone-700 text-stone-200 text-sm font-semibold rounded-xl border border-stone-700 transition-colors flex items-center gap-2"
            >
              <Clock className="w-4 h-4 text-orange-400" />
              <span>Try Growing Message Pilot</span>
            </button>
          </div>
        </div>

        {/* Subtle decorative background graphic */}
        <div className="absolute -right-10 -bottom-10 opacity-15 pointer-events-none hidden md:block">
          <svg className="w-96 h-96 fill-orange-500" viewBox="0 0 71 48">
            <path d="m26.371 33.477-.552-.1c-3.92-.729-6.397-3.1-7.57-6.829-.733-2.324.597-4.035 3.035-4.148 1.995-.092 3.362 1.055 4.57 2.39 1.557 1.72 2.984 3.558 4.514 5.305 2.202 2.515 4.797 4.134 8.347 3.634 3.183-.448 5.958-1.725 8.371-3.828.363-.316.761-.592 1.144-.886l-.241-.284c-2.027.63-4.093.841-6.205.735-3.195-.16-6.24-.828-8.964-2.582-2.486-1.601-4.319-3.746-5.19-6.611-.704-2.315.736-3.934 3.135-3.6.948.133 1.746.56 2.463 1.165.583.493 1.143 1.015 1.738 1.493 2.8 2.25 6.712 2.375 10.265-.068-5.842-.026-9.817-3.24-13.308-7.313-1.366-1.594-2.7-3.216-4.095-4.785-2.698-3.036-5.692-5.71-9.79-6.623C12.8-.623 7.745.14 2.893 2.361 1.926 2.804.997 3.319 0 4.149c.494 0 .763.006 1.032 0 2.446-.064 4.28 1.023 5.602 3.024.962 1.457 1.415 3.104 1.761 4.798.513 2.515.247 5.078.544 7.605.761 6.494 4.08 11.026 10.26 13.346 2.267.852 4.591 1.135 7.172.555Z" />
          </svg>
        </div>
      </div>

      {/* Categories Grid (Screen: Home §5) */}
      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-stone-900 dark:text-stone-50 font-serif">
            Categories
          </h2>
          <span className="text-xs text-stone-500">
            {categories.length} active categories
          </span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {categories.map((category) => {
            const count = topics.filter(t => t.categoryId === category.id).length;
            const latestTopic = topics
              .filter(t => t.categoryId === category.id)
              .sort((a, b) => b.id.localeCompare(a.id))[0];

            return (
              <div
                key={category.id}
                onClick={() => onSelectCategory(category)}
                className="group p-5 rounded-2xl bg-white dark:bg-stone-900 border border-stone-200/80 dark:border-stone-800 hover:border-orange-400 dark:hover:border-orange-600/80 shadow-xs hover:shadow-md transition-all cursor-pointer flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-center justify-between gap-3 mb-2.5">
                    <div className="flex items-center gap-2.5">
                      <span
                        className="w-3.5 h-3.5 rounded-full ring-2 ring-stone-100 dark:ring-stone-800"
                        style={{ backgroundColor: category.color }}
                      />
                      <h3 className="font-bold text-base text-stone-900 dark:text-stone-100 group-hover:text-orange-600 dark:group-hover:text-orange-400 transition-colors">
                        {category.name}
                      </h3>
                    </div>

                    <span className="text-xs px-2 py-0.5 rounded-full bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-400 font-medium">
                      {count} {count === 1 ? 'topic' : 'topics'}
                    </span>
                  </div>

                  <p className="text-xs sm:text-sm text-stone-600 dark:text-stone-400 leading-relaxed line-clamp-2">
                    {category.description}
                  </p>
                </div>

                <div className="mt-4 pt-3 border-t border-stone-100 dark:border-stone-800 flex items-center justify-between text-xs text-stone-500">
                  <span className="truncate max-w-[240px]">
                    {latestTopic ? (
                      <>Latest: <strong className="text-stone-700 dark:text-stone-300">{latestTopic.title}</strong></>
                    ) : (
                      'No topics yet'
                    )}
                  </span>
                  <span className="flex items-center gap-1 text-orange-600 dark:text-orange-400 font-semibold group-hover:translate-x-0.5 transition-transform">
                    <span>Enter</span>
                    <ArrowRight className="w-3.5 h-3.5" />
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* Featured / Active Topics */}
      <section className="space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-stone-900 dark:text-stone-50 font-serif flex items-center gap-2">
            <Flame className="w-4 h-4 text-orange-500" />
            <span>Active Topics</span>
          </h2>
          <span className="text-xs text-stone-500">
            Across all categories
          </span>
        </div>

        <div className="space-y-2.5">
          {featuredTopics.map((topic) => {
            const cat = categories.find(c => c.id === topic.categoryId);
            return (
              <div
                key={topic.id}
                onClick={() => onSelectTopic(topic)}
                className="group p-4 rounded-xl bg-white dark:bg-stone-900 border border-stone-200/80 dark:border-stone-800 hover:border-orange-400 dark:hover:border-orange-600 transition-all cursor-pointer flex items-center justify-between gap-4"
              >
                <div className="flex items-center gap-3 min-w-0">
                  {cat && (
                    <span
                      className="w-2.5 h-2.5 rounded-full shrink-0"
                      style={{ backgroundColor: cat.color }}
                      title={cat.name}
                    />
                  )}

                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      {topic.pinned && (
                        <span className="text-[10px] font-bold px-1.5 py-0.2 bg-amber-100 text-amber-800 dark:bg-amber-950/60 dark:text-amber-300 rounded">
                          PINNED
                        </span>
                      )}
                      <h4 className="font-semibold text-sm text-stone-900 dark:text-stone-100 group-hover:text-orange-600 dark:group-hover:text-orange-400 transition-colors truncate">
                        {topic.title}
                      </h4>
                    </div>
                    <span className="text-xs text-stone-400 mt-0.5 block truncate">
                      {topic.author.displayName} &bull; {cat?.name} &bull; {topic.lastActivityAt}
                    </span>
                  </div>
                </div>

                <div className="flex items-center gap-1.5 text-xs text-stone-500 shrink-0 font-medium">
                  <MessageSquare className="w-3.5 h-3.5 text-stone-400" />
                  <span>{topic.messageCount}</span>
                </div>
              </div>
            );
          })}
        </div>
      </section>
    </div>
  );
};
