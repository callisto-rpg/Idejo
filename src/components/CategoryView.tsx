import React, { useState } from 'react';
import { 
  PlusCircle, 
  Pin, 
  Lock, 
  MessageSquare, 
  Clock, 
  ArrowLeft,
  Sparkles,
  GitFork
} from 'lucide-react';
import { Category, Topic } from '../types';

interface CategoryViewProps {
  category: Category;
  topics: Topic[];
  onSelectTopic: (topic: Topic) => void;
  onNewTopic: (prefillCategoryId?: string) => void;
  onBackToHome: () => void;
}

export const CategoryView: React.FC<CategoryViewProps> = ({
  category,
  topics,
  onSelectTopic,
  onNewTopic,
  onBackToHome,
}) => {
  const [filter, setFilter] = useState<'all' | 'pinned'>('all');

  // Filter and sort: Pinned first (TP-03)
  const categoryTopics = topics
    .filter(t => t.categoryId === category.id)
    .filter(t => (filter === 'pinned' ? t.pinned : true))
    .sort((a, b) => {
      if (a.pinned && !b.pinned) return -1;
      if (!a.pinned && b.pinned) return 1;
      return 0;
    });

  return (
    <div className="max-w-5xl mx-auto px-4 sm:px-6 py-6 space-y-6">
      {/* Category Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-6 border-b border-stone-200 dark:border-stone-800">
        <div className="space-y-2">
          <button
            onClick={onBackToHome}
            className="inline-flex items-center gap-1.5 text-xs font-medium text-stone-500 hover:text-orange-600 dark:hover:text-orange-400 transition-colors"
          >
            <ArrowLeft className="w-3.5 h-3.5" />
            <span>All Categories</span>
          </button>

          <div className="flex items-center gap-3">
            <span
              className="w-4 h-4 rounded-full shrink-0"
              style={{ backgroundColor: category.color }}
            />
            <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-stone-900 dark:text-stone-50 font-serif">
              {category.name}
            </h1>
          </div>
          <p className="text-sm text-stone-600 dark:text-stone-400 max-w-2xl">
            {category.description}
          </p>
        </div>

        <button
          onClick={() => onNewTopic(category.id)}
          className="inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-orange-600 hover:bg-orange-700 active:bg-orange-800 text-white font-medium text-sm rounded-xl shadow-sm shadow-orange-600/25 transition-all self-start sm:self-center"
        >
          <PlusCircle className="w-4 h-4" />
          <span>New Topic in {category.name}</span>
        </button>
      </div>

      {/* Filter tabs */}
      <div className="flex items-center gap-2 border-b border-stone-200 dark:border-stone-800 text-xs pb-3">
        <button
          onClick={() => setFilter('all')}
          className={`px-3 py-1.5 rounded-lg font-medium transition-colors ${
            filter === 'all'
              ? 'bg-stone-900 text-white dark:bg-stone-100 dark:text-stone-900'
              : 'text-stone-600 dark:text-stone-400 hover:bg-stone-100 dark:hover:bg-stone-800'
          }`}
        >
          All Topics ({topics.filter(t => t.categoryId === category.id).length})
        </button>
        <button
          onClick={() => setFilter('pinned')}
          className={`px-3 py-1.5 rounded-lg font-medium transition-colors ${
            filter === 'pinned'
              ? 'bg-stone-900 text-white dark:bg-stone-100 dark:text-stone-900'
              : 'text-stone-600 dark:text-stone-400 hover:bg-stone-100 dark:hover:bg-stone-800'
          }`}
        >
          Pinned ({topics.filter(t => t.categoryId === category.id && t.pinned).length})
        </button>
      </div>

      {/* Topic List (TP-03) */}
      <div className="space-y-3">
        {categoryTopics.length === 0 ? (
          <div className="text-center py-12 bg-white dark:bg-stone-900 border border-dashed border-stone-300 dark:border-stone-700 rounded-2xl p-8">
            <MessageSquare className="w-10 h-10 text-stone-300 dark:text-stone-600 mx-auto mb-3" />
            <h3 className="text-base font-semibold text-stone-800 dark:text-stone-200">
              No topics in this category yet
            </h3>
            <p className="text-xs text-stone-500 mt-1 max-w-sm mx-auto mb-4">
              Be the first community member to start a discussion in {category.name}!
            </p>
            <button
              onClick={() => onNewTopic(category.id)}
              className="px-4 py-2 bg-orange-600 hover:bg-orange-700 text-white text-xs font-semibold rounded-lg shadow-sm"
            >
              Start the first topic
            </button>
          </div>
        ) : (
          categoryTopics.map((topic) => (
            <div
              key={topic.id}
              onClick={() => onSelectTopic(topic)}
              className="group p-4 sm:p-5 rounded-2xl bg-white dark:bg-stone-900 border border-stone-200/80 dark:border-stone-800 hover:border-orange-400 dark:hover:border-orange-600/80 shadow-xs hover:shadow-md transition-all cursor-pointer flex flex-col sm:flex-row sm:items-center justify-between gap-4"
            >
              <div className="space-y-1.5 flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  {topic.pinned && (
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-amber-100 text-amber-800 dark:bg-amber-950/60 dark:text-amber-300">
                      <Pin className="w-3 h-3" />
                      Pinned
                    </span>
                  )}
                  {topic.state === 'locked' && (
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-red-100 text-red-800 dark:bg-red-950/60 dark:text-red-300">
                      <Lock className="w-3 h-3" />
                      Locked
                    </span>
                  )}
                  {topic.forkedFromMessageId && (
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-medium bg-stone-100 text-stone-600 dark:bg-stone-800 dark:text-stone-300">
                      <GitFork className="w-3 h-3" />
                      Forked
                    </span>
                  )}
                </div>

                <h3 className="text-base sm:text-lg font-bold text-stone-900 dark:text-stone-100 group-hover:text-orange-600 dark:group-hover:text-orange-400 transition-colors truncate">
                  {topic.title}
                </h3>

                <div className="flex items-center gap-2 text-xs text-stone-500">
                  <span className="flex items-center gap-1.5">
                    <img
                      src={topic.author.avatar}
                      alt={topic.author.displayName}
                      className="w-4 h-4 rounded-full object-cover"
                    />
                    <span>{topic.author.displayName}</span>
                  </span>
                  <span>&bull;</span>
                  <span>{topic.lastActivityAt}</span>
                </div>
              </div>

              {/* Right stats */}
              <div className="flex items-center gap-4 sm:flex-col sm:items-end sm:gap-1 text-xs text-stone-500 shrink-0">
                <div className="flex items-center gap-1.5 font-medium text-stone-700 dark:text-stone-300 bg-stone-100 dark:bg-stone-800 px-2.5 py-1 rounded-lg">
                  <MessageSquare className="w-3.5 h-3.5 text-orange-500" />
                  <span>{topic.messageCount} messages</span>
                </div>
                {topic.unreadCount && topic.unreadCount > 0 ? (
                  <span className="px-2 py-0.5 text-[10px] font-bold bg-orange-600 text-white rounded-full">
                    {topic.unreadCount} unread
                  </span>
                ) : null}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
