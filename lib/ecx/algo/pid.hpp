#pragma once
#include <concepts>

namespace ecx::algo
{

// Discrete PID controller with anti-windup output clamping.
// T must be a floating-point type (float or double).
template <std::floating_point T>
class Pid
{
public:
    constexpr Pid(T kp, T ki, T kd, T output_limit)
        : kp_(kp), ki_(ki), kd_(kd), limit_(output_limit)
    {
    }

    // Compute one control step. dt is the time elapsed since the last call (seconds).
    T update(T setpoint, T feedback, T dt)
    {
        const T err = setpoint - feedback;
        integral_ += err * dt;
        const T derivative = (err - prev_err_) / dt;
        prev_err_          = err;

        T out = kp_ * err + ki_ * integral_ + kd_ * derivative;

        // Clamp output and prevent integral wind-up beyond the clamp boundary.
        if (out > limit_) {
            out = limit_;
            if (err > T{0}) integral_ -= err * dt;
        } else if (out < -limit_) {
            out = -limit_;
            if (err < T{0}) integral_ -= err * dt;
        }
        return out;
    }

    void reset()
    {
        integral_ = T{0};
        prev_err_ = T{0};
    }

    void set_gains(T kp, T ki, T kd)
    {
        kp_ = kp;
        ki_ = ki;
        kd_ = kd;
    }

private:
    T kp_, ki_, kd_, limit_;
    T integral_{};
    T prev_err_{};
};

}  // namespace ecx::algo
