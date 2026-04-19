<?php

namespace App\Notifications;

use App\Models\Order;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class OrderPaymentNotification extends Notification
{
    use Queueable;

    public function __construct(
        private readonly Order $order,
        private readonly string $title,
        private readonly string $message,
        private readonly string $level = 'info'
    ) {
    }

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        return [
            'title' => $this->title,
            'message' => $this->message,
            'level' => $this->level,
            'order_id' => $this->order->id,
            'url' => $notifiable->isAdmin()
                ? route('admin.orders.show', $this->order->id)
                : route('orders.show', $this->order->id),
        ];
    }
}
