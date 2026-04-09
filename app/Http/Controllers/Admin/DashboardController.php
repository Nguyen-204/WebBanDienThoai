<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\Order;
use App\Models\User;

class DashboardController extends Controller
{
    public function index()
    {
        $stats = [
            'products' => Product::count(),
            'orders' => Order::count(),
            'customers' => User::where('role', 'customer')->count(),
            'revenue' => Order::where('status', 'completed')->sum('total'),
            'pendingQrPayments' => Order::where('payment_method', Order::PAYMENT_METHOD_QR)
                ->where('payment_status', Order::PAYMENT_STATUS_PENDING_CONFIRMATION)
                ->count(),
        ];

        $recentOrders = Order::with('user')->latest()->take(5)->get();
        $recentOrders->each->syncPaymentState();

        return view('admin.dashboard', compact('stats', 'recentOrders'));
    }
}
