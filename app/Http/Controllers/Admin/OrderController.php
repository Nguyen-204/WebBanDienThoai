<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\Product;
use App\Notifications\OrderPaymentNotification;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class OrderController extends Controller
{
    public function index(Request $request)
    {
        $query = Order::with('user')->latest();

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('payment_status')) {
            $query->where('payment_status', $request->payment_status);
        }

        $orders = $query->paginate(15)->appends($request->query());
        $orders->getCollection()->each->syncPaymentState();

        return view('admin.orders.index', compact('orders'));
    }

    public function show($id)
    {
        $order = Order::with(['user', 'items'])->findOrFail($id);
        $order->syncPaymentState();

        return view('admin.orders.show', compact('order'));
    }

    public function updateStatus(Request $request, $id)
    {
        $request->validate([
            'status' => 'required|in:' . implode(',', array_keys(Order::statusOptions())),
        ]);

        $newStatus = $request->status;

        DB::transaction(function () use ($id, $newStatus) {
            $order = Order::with('items')->findOrFail($id);
            $order->syncPaymentState();
            $currentStatus = $order->status;

            if (!$order->canTransitionTo($newStatus)) {
                throw ValidationException::withMessages([
                    'status' => 'Không thể chuyển đơn từ trạng thái hiện tại sang trạng thái này.',
                ]);
            }

            if ($currentStatus === $newStatus) {
                return;
            }

            if ($currentStatus !== Order::STATUS_CANCELLED && $newStatus === Order::STATUS_CANCELLED) {
                foreach ($order->items as $item) {
                    $product = Product::find($item->product_id);

                    if ($product) {
                        $product->increment('stock', $item->quantity);
                    }
                }
            }

            if ($currentStatus === Order::STATUS_CANCELLED && $newStatus !== Order::STATUS_CANCELLED) {
                foreach ($order->items as $item) {
                    $product = Product::find($item->product_id);

                    if (!$product) {
                        throw ValidationException::withMessages([
                            'status' => 'Không thể khôi phục đơn vì một số sản phẩm không còn tồn tại.',
                        ]);
                    }

                    if ($product->stock < $item->quantity) {
                        throw ValidationException::withMessages([
                            'status' => 'Không đủ tồn kho để chuyển đơn khỏi trạng thái hủy.',
                        ]);
                    }

                    $product->decrement('stock', $item->quantity);
                }
            }

            $order->update(['status' => $newStatus]);
        });

        return redirect()->route('admin.orders.show', $id)
            ->with('success', 'Đã cập nhật trạng thái đơn hàng.');
    }

    public function confirmPayment($id)
    {
        $order = Order::with('user')->findOrFail($id);
        $order->syncPaymentState();

        if (!$order->canConfirmQrPayment()) {
            return redirect()->route('admin.orders.show', $order->id)
                ->with('error', 'Đơn hàng này không ở trạng thái chờ xác nhận thanh toán QR.');
        }

        $order->update([
            'payment_status' => Order::PAYMENT_STATUS_PAID,
            'payment_confirmed_at' => now(),
        ]);

        if ($order->user) {
            $order->user->notify(new OrderPaymentNotification(
                $order,
                'Thanh toán QR đã được xác nhận',
                'Đơn #' . $order->id . ' đã được admin xác nhận thanh toán thành công.',
                'success'
            ));
        }

        return redirect()->route('admin.orders.show', $order->id)
            ->with('success', 'Đã xác nhận thanh toán QR cho đơn hàng.');
    }

    public function rejectPayment($id)
    {
        $order = Order::with('user')->findOrFail($id);
        $order->syncPaymentState();

        if (!$order->canConfirmQrPayment()) {
            return redirect()->route('admin.orders.show', $order->id)
                ->with('error', 'Đơn hàng này không có yêu cầu xác nhận thanh toán nào đang mở.');
        }

        $paymentStatus = $order->isQrExpired()
            ? Order::PAYMENT_STATUS_EXPIRED
            : Order::PAYMENT_STATUS_WAITING_TRANSFER;

        $order->update([
            'payment_status' => $paymentStatus,
            'payment_requested_at' => null,
        ]);

        if ($order->user) {
            $order->user->notify(new OrderPaymentNotification(
                $order,
                'Yêu cầu thanh toán QR chưa được duyệt',
                'Admin đã từ chối yêu cầu xác nhận thanh toán của đơn #' . $order->id . '. Vui lòng kiểm tra và gửi lại nếu cần.',
                'danger'
            ));
        }

        return redirect()->route('admin.orders.show', $order->id)
            ->with('success', 'Đã từ chối yêu cầu xác nhận thanh toán QR.');
    }
}
