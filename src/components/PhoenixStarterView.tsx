import React from 'react';
import { ExternalLink, BookOpen, GitBranch, MessageSquare, Terminal, FileCode2 } from 'lucide-react';

interface PhoenixStarterViewProps {
  onReturnToForum: () => void;
}

export const PhoenixStarterView: React.FC<PhoenixStarterViewProps> = ({ onReturnToForum }) => {
  return (
    <div className="relative min-h-[calc(100vh-4rem)] overflow-hidden bg-white dark:bg-stone-950 text-stone-900 dark:text-stone-100">
      {/* Background decoration from original Phoenix starter */}
      <div className="left-[40rem] fixed inset-y-0 right-0 z-0 hidden lg:block xl:left-[50rem] pointer-events-none opacity-80">
        <svg
          viewBox="0 0 1480 957"
          fill="none"
          aria-hidden="true"
          className="absolute inset-0 h-full w-full"
          preserveAspectRatio="xMinYMid slice"
        >
          <path fill="#EE7868" d="M0 0h1480v957H0z" />
          <path
            d="M137.542 466.27c-582.851-48.41-988.806-82.127-1608.412 658.2l67.39 810 3083.15-256.51L1535.94-49.622l-98.36 8.183C1269.29 281.468 734.115 515.799 146.47 467.012l-8.928-.742Z"
            fill="#FF9F92"
          />
          <path
            d="M371.028 528.664C-169.369 304.988-545.754 149.198-1361.45 665.565l-182.58 792.025 3014.73 694.98 389.42-1689.25-96.18-22.171C1505.28 697.438 924.153 757.586 379.305 532.09l-8.277-3.426Z"
            fill="#FA8372"
          />
          <path
            d="M359.326 571.714C-104.765 215.795-428.003-32.102-1349.55 255.554l-282.3 1224.596 3047.04 722.01 312.24-1354.467C1411.25 1028.3 834.355 935.995 366.435 577.166l-7.109-5.452Z"
            fill="#E96856"
            fillOpacity=".6"
          />
          <path
            d="M1593.87 1236.88c-352.15 92.63-885.498-145.85-1244.602-613.557l-5.455-7.105C-12.347 152.31-260.41-170.8-1225-131.458l-368.63 1599.048 3057.19 704.76 130.31-935.47Z"
            fill="#C42652"
            fillOpacity=".2"
          />
          <path
            d="M1411.91 1526.93c-363.79 15.71-834.312-330.6-1085.883-863.909l-3.822-8.102C72.704 125.95-101.074-242.476-1052.01-408.907l-699.85 1484.267 2837.75 1338.01 326.02-886.44Z"
            fill="#A41C42"
            fillOpacity=".2"
          />
        </svg>
      </div>

      <div className="relative z-10 px-4 py-10 sm:px-6 sm:py-20 lg:px-8 xl:px-28">
        <div className="mx-auto max-w-xl lg:mx-0">
          {/* Logo */}
          <div className="flex items-center gap-3">
            <svg viewBox="0 0 71 48" className="h-10 fill-[#FD4F00]" aria-hidden="true">
              <path d="m26.371 33.477-.552-.1c-3.92-.729-6.397-3.1-7.57-6.829-.733-2.324.597-4.035 3.035-4.148 1.995-.092 3.362 1.055 4.57 2.39 1.557 1.72 2.984 3.558 4.514 5.305 2.202 2.515 4.797 4.134 8.347 3.634 3.183-.448 5.958-1.725 8.371-3.828.363-.316.761-.592 1.144-.886l-.241-.284c-2.027.63-4.093.841-6.205.735-3.195-.16-6.24-.828-8.964-2.582-2.486-1.601-4.319-3.746-5.19-6.611-.704-2.315.736-3.934 3.135-3.6.948.133 1.746.56 2.463 1.165.583.493 1.143 1.015 1.738 1.493 2.8 2.25 6.712 2.375 10.265-.068-5.842-.026-9.817-3.24-13.308-7.313-1.366-1.594-2.7-3.216-4.095-4.785-2.698-3.036-5.692-5.71-9.79-6.623C12.8-.623 7.745.14 2.893 2.361 1.926 2.804.997 3.319 0 4.149c.494 0 .763.006 1.032 0 2.446-.064 4.28 1.023 5.602 3.024.962 1.457 1.415 3.104 1.761 4.798.513 2.515.247 5.078.544 7.605.761 6.494 4.08 11.026 10.26 13.346 2.267.852 4.591 1.135 7.172.555Z" />
            </svg>
            <span className="font-bold text-xl tracking-tight">Idejo Foundations</span>
          </div>

          <div className="mt-8 flex items-center gap-3">
            <span className="text-sm font-semibold leading-6">Phoenix Framework</span>
            <span className="px-2 py-0.5 rounded text-xs font-semibold bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300">
              v1.8 &bull; M0 Baseline
            </span>
          </div>

          <p className="text-3xl sm:text-4xl mt-3 font-semibold tracking-tight text-balance font-serif">
            Peace of mind from prototype to production.
          </p>

          <p className="mt-4 leading-relaxed text-stone-600 dark:text-stone-300 text-sm sm:text-base">
            This repository originated from <strong>callisto-rpg/Idejo</strong> as Milestone M0 (Foundations). It has now been migrated to an interactive, deployable Node.js / React application with the full Growing Message conversation engine running in AI Studio!
          </p>

          <div className="mt-6 flex flex-wrap gap-3">
            <button
              onClick={onReturnToForum}
              className="px-5 py-2.5 bg-orange-600 hover:bg-orange-700 text-white font-semibold text-sm rounded-xl shadow-md transition-all"
            >
              Open Idejo Community Forum
            </button>
          </div>

          {/* Quick doc cards */}
          <div className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3">
            <a
              href="https://phoenix.hexdocs.pm/overview.html"
              target="_blank"
              rel="noreferrer"
              className="p-4 rounded-2xl bg-stone-100 dark:bg-stone-900 hover:bg-stone-200 dark:hover:bg-stone-800 transition-colors border border-stone-200/80 dark:border-stone-800 group"
            >
              <BookOpen className="h-6 w-6 text-orange-600 mb-2 group-hover:scale-110 transition-transform" />
              <div className="font-semibold text-sm">Guides &amp; Docs</div>
              <p className="text-xs text-stone-500 mt-1">Phoenix overview and guides</p>
            </a>

            <a
              href="https://github.com/callisto-rpg/Idejo"
              target="_blank"
              rel="noreferrer"
              className="p-4 rounded-2xl bg-stone-100 dark:bg-stone-900 hover:bg-stone-200 dark:hover:bg-stone-800 transition-colors border border-stone-200/80 dark:border-stone-800 group"
            >
              <GitBranch className="h-6 w-6 text-stone-800 dark:text-stone-200 mb-2 group-hover:scale-110 transition-transform" />
              <div className="font-semibold text-sm">Original Repo</div>
              <p className="text-xs text-stone-500 mt-1">callisto-rpg/Idejo on GitHub</p>
            </a>

            <a
              href="https://elixirforum.com"
              target="_blank"
              rel="noreferrer"
              className="p-4 rounded-2xl bg-stone-100 dark:bg-stone-900 hover:bg-stone-200 dark:hover:bg-stone-800 transition-colors border border-stone-200/80 dark:border-stone-800 group"
            >
              <MessageSquare className="h-6 w-6 text-purple-600 mb-2 group-hover:scale-110 transition-transform" />
              <div className="font-semibold text-sm">Elixir Forum</div>
              <p className="text-xs text-stone-500 mt-1">Join the community</p>
            </a>
          </div>
        </div>
      </div>
    </div>
  );
};
