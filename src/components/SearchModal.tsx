import React, { useState } from 'react';
import { Search, X, MessageSquare, ArrowRight, CornerDownRight } from 'lucide-react';
import { Topic, Message, Category } from '../types';

interface SearchModalProps {
  topics: Topic[];
  messages: Message[];
  categories: Category[];
  onClose: () => void;
  onSelectTopic: (topic: Topic) => void;
}

export const SearchModal: React.FC<SearchModalProps> = ({
  topics,
  messages,
  categories,
  onClose,
  onSelectTopic,
}) => {
  const [query, setQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');

  const trimmed = query.trim().toLowerCase();

  // Search matching topics
  const matchingTopics = topics.filter((t) => {
    if (selectedCategory !== 'all' && t.categoryId !== selectedCategory) {
      return false;
    }
    if (!trimmed) return true;
    return t.title.toLowerCase().includes(trimmed);
  });

  // Search matching messages (SE-01 to SE-03)
  const matchingMessages = trimmed
    ? messages.filter((m) => {
        const topic = topics.find((t) => t.id === m.topicId);
        if (!topic) return false;
        if (selectedCategory !== 'all' && topic.categoryId !== selectedCategory) {
          return false;
        }
        return m.bodyMd.toLowerCase().includes(trimmed);
      })
    : [];

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-start justify-center p-4 pt-16 sm:pt-24">
      <div className="bg-white dark:bg-stone-900 rounded-3xl max-w-2xl w-full shadow-2xl border border-stone-200 dark:border-stone-800 overflow-hidden flex flex-col max-h-[80vh]">
        {/* Search Input Bar */}
        <div className="p-4 border-b border-stone-200 dark:border-stone-800 flex items-center gap-3">
          <Search className="w-5 h-5 text-stone-400 shrink-0" />
          <input
            type="text"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search keywords, topics, or message contents..."
            className="w-full bg-transparent text-sm sm:text-base text-stone-900 dark:text-stone-100 placeholder-stone-400 focus:outline-none"
          />
          {query && (
            <button
              onClick={() => setQuery('')}
              className="p-1 text-stone-400 hover:text-stone-600 rounded"
            >
              <X className="w-4 h-4" />
            </button>
          )}
          <button
            onClick={onClose}
            className="p-1.5 text-stone-400 hover:text-stone-600 dark:hover:text-stone-200 rounded-lg hover:bg-stone-100 dark:hover:bg-stone-800 text-xs font-semibold"
          >
            Esc
          </button>
        </div>

        {/* Category Filter Pills */}
        <div className="px-4 py-2.5 bg-stone-50 dark:bg-stone-950/50 border-b border-stone-200 dark:border-stone-800 flex items-center gap-2 overflow-x-auto text-xs">
          <span className="text-stone-400 font-medium shrink-0">Category:</span>
          <button
            onClick={() => setSelectedCategory('all')}
            className={`px-2.5 py-1 rounded-full font-medium transition-colors shrink-0 ${
              selectedCategory === 'all'
                ? 'bg-orange-600 text-white'
                : 'bg-stone-200/60 dark:bg-stone-800 text-stone-600 dark:text-stone-400 hover:bg-stone-300 dark:hover:bg-stone-700'
            }`}
          >
            All Categories
          </button>
          {categories.map((c) => (
            <button
              key={c.id}
              onClick={() => setSelectedCategory(c.id)}
              className={`px-2.5 py-1 rounded-full font-medium transition-colors shrink-0 flex items-center gap-1.5 ${
                selectedCategory === c.id
                  ? 'bg-stone-900 text-white dark:bg-stone-100 dark:text-stone-900'
                  : 'bg-stone-200/60 dark:bg-stone-800 text-stone-600 dark:text-stone-400 hover:bg-stone-300 dark:hover:bg-stone-700'
              }`}
            >
              <span
                className="w-2 h-2 rounded-full"
                style={{ backgroundColor: c.color }}
              />
              <span>{c.name}</span>
            </button>
          ))}
        </div>

        {/* Search Results Area */}
        <div className="p-4 space-y-4 overflow-y-auto flex-1">
          {/* Matching Topics */}
          <div>
            <h4 className="text-[11px] font-bold uppercase tracking-wider text-stone-400 mb-2">
              Topics ({matchingTopics.length})
            </h4>

            {matchingTopics.length === 0 ? (
              <p className="text-xs text-stone-500 italic py-2">No topics found</p>
            ) : (
              <div className="space-y-1.5">
                {matchingTopics.slice(0, 5).map((topic) => {
                  const cat = categories.find((c) => c.id === topic.categoryId);
                  return (
                    <div
                      key={topic.id}
                      onClick={() => {
                        onSelectTopic(topic);
                        onClose();
                      }}
                      className="p-3 rounded-xl hover:bg-stone-100 dark:hover:bg-stone-800 cursor-pointer flex items-center justify-between transition-colors group"
                    >
                      <div className="min-w-0 pr-3">
                        <div className="font-semibold text-sm text-stone-900 dark:text-stone-100 group-hover:text-orange-600 dark:group-hover:text-orange-400 truncate">
                          {topic.title}
                        </div>
                        <div className="text-xs text-stone-400 flex items-center gap-2 mt-0.5">
                          <span>{cat?.name}</span>
                          <span>&bull;</span>
                          <span>{topic.messageCount} messages</span>
                        </div>
                      </div>
                      <ArrowRight className="w-4 h-4 text-stone-400 group-hover:text-orange-600 group-hover:translate-x-1 transition-all shrink-0" />
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Matching Message Bodies (SE-02, SE-03) */}
          {trimmed && (
            <div>
              <h4 className="text-[11px] font-bold uppercase tracking-wider text-stone-400 mb-2">
                Messages containing "{query}" ({matchingMessages.length})
              </h4>

              {matchingMessages.length === 0 ? (
                <p className="text-xs text-stone-500 italic py-2">No matching messages</p>
              ) : (
                <div className="space-y-2">
                  {matchingMessages.slice(0, 5).map((msg) => {
                    const topic = topics.find((t) => t.id === msg.topicId);
                    if (!topic) return null;

                    return (
                      <div
                        key={msg.id}
                        onClick={() => {
                          onSelectTopic(topic);
                          onClose();
                        }}
                        className="p-3 rounded-xl border border-stone-200/80 dark:border-stone-800 hover:border-orange-400 cursor-pointer transition-colors"
                      >
                        <div className="flex items-center justify-between text-xs text-stone-500 mb-1">
                          <span className="font-medium text-stone-700 dark:text-stone-300">
                            {msg.author.displayName} in <strong>{topic.title}</strong>
                          </span>
                          <span>{new Date(msg.openedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                        </div>
                        <p className="text-xs text-stone-700 dark:text-stone-300 line-clamp-2 italic bg-stone-50 dark:bg-stone-950 p-2 rounded border border-stone-100 dark:border-stone-800">
                          "{msg.bodyMd}"
                        </p>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
