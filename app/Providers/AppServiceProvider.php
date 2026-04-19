<?php

namespace App\Providers;

use App\Models\Order;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\View;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        View::composer(['layouts.app', 'layouts.admin'], function ($view) {
            $user = Auth::user();

            if (!$user) {
                $view->with('navNotifications', collect());
                $view->with('unreadNotificationCount', 0);
                $view->with('adminPendingQrCount', 0);
                return;
            }

            $view->with('navNotifications', $user->notifications()->latest()->take(6)->get());
            $view->with('unreadNotificationCount', $user->unreadNotifications()->count());

            $adminPendingQrCount = $user->isAdmin()
                ? Order::query()
                    ->where('payment_method', Order::PAYMENT_METHOD_QR)
                    ->where('payment_status', Order::PAYMENT_STATUS_PENDING_CONFIRMATION)
                    ->count()
                : 0;

            $view->with('adminPendingQrCount', $adminPendingQrCount);
        });
    }
}
