function [q_path, X_path, Time, H, success] = mostLikelyGrade(q0, ...
    Euler_v, L, steps, obstacle, robot)
% 最似梯度法(most likely grade method, MLG法)进行机械臂逆运动学轨迹优化，通过
% 迭代的方法求解关节角q及速度dq
% 输入参数:
% q0为初始关节变量
% Euler_v为末端执行器欧拉角速度
% L表示机械臂运动总路程
% steps对给定的轨迹进行直线插补的总小段数
% obstacle表示障碍物信息
% robot为机械臂DH等相关数据
% 输出参数:
% q为最优关节轨迹
% X为q对应的位姿轨迹
% rE为机械臂末端位置矢量
% RE为机械臂末端姿态矩阵
% P0(:,n)为机械臂第n个避障特征点位置矢量
% Time为时间序列
% H为目标函数
% success为标志变量：若success=1，表示规划成功；若success=0,表示规划不成功。

% global variables
global COMPILE
% 载入机械臂参数
n = robot.n;
m = robot.m;
q_max = robot.q_max;
q_min = robot.q_min;
a_max = robot.acce_max;
% n为关节变量维数
% q_max、q_min为关节变量的上下限
% a_max表示关节速度大小变化的最大值
% n为自由度
% m为末端自由度，限制为6


% initialization
q_path = zeros(n, steps + 1);
dq = zeros(n, steps);
X_path = zeros(m, steps + 1);
Time = zeros(1, steps + 1);
s = zeros(1, steps + 1);
X_s = zeros(m, 1);
factor = zeros(1, n);
zero_norm = (1e-3)^6;
delta_L = L / double(steps);
allow_error = 0.1; % distance between the final resolved point with the 
% goal point which is allowed 
success = 1;
% band the minimum velocity
v_min = 0.05;
% normalize the euler velocity
Euler_v = Euler_v / norm(Euler_v);
i = 1;
dq(:, 1) = zeros(n, 1);
q_path(:, i) = q0;
X_s(1:3) = Euler_v(1:3);
while i <= steps
    % get jacobi matrix and relative useful matrix
    [jac, ~, ra, pa, ~, ~] = Jacobi(q_path(1:n, i), robot);
    % perform euler angle velocity
    X_path(1:6, i) = matrix2pose(ra(:, :, n+1), pa(:, n+1));
    X_s(4:6) = eulerV2absV(X_path(4:6), Euler_v(4:6));
    % to do boundary & obstacle detect
    if ~(obstacleFree([X_path(1:3,i) pa(:, :)], obstacle)  ...
            && boundaryFree(q_path(:, i), q_max, q_min))
        success = 0;
        break;
    end
    % to see if jtj is strange
    jtj = jac * jac';
    det_jtj = det(jtj);
    if zero_norm < abs(det_jtj)
        % pinv means expand inverse of jac, that is , j_pinv = jac'/jtj
        j_pinv = jac'/jtj;
        Y = j_pinv * X_s;
        A = eye(n) - j_pinv * jac;
        dH = gradMLG(q_path(:, i), q_max, q_min, n);
        % column transformation in l-u deformation
        [~, u, ~] = lu(A'); 
        % get B from B's transposition, that A = [B 0]*Q
        B = u';
        B = B(:, n-m);
        % compute ds and velocity
        main_matrix = [Y'*Y, Y'*B; B'*Y, B'*B];
        ds_vel = -1/2*( main_matrix\[Y'*dH; B'*dH] );
        ds = ds_vel(1, 1);
        vel = ds_vel(2, 1);
        % to see if ds is big enough
        if ds < v_min
            vel = vel*v_min/ds;
            ds = v_min;
        end
        % compute dq
        dq(:, i+1) = Y*ds + B*vel;
        % to see if accelerate is suitable, if not, suitify it
        t = delta_L / ds;
        for j = 1:n
            factor(j) = abs(dq(j, i+1) - dq(j, i))/t/a_max(j);
        end
        max_fac = max(factor);
        if 1 < max_fac
            ds = ds / max_fac;
            vel = vel / max_fac;
        end
        if ds < v_min
            ds = v_min;
        end
        % after doing things above, get the ending dq
        dq(:, i+1) = Y*ds + B*vel;
        t = delta_L / ds;
        Time(i + 1) = Time(i) + t;
        q_path(:, i+1) = q_path(:, i) + dq(:, i+1)*t;
        s(i+1) = s(i) + ds*t;
        % compile output
        COMPILE = 0;
        if COMPILE 
            toolkit('matrix', Y, 'Y is: ');
            toolkit('matrix', B, 'B is: ');
            toolkit('matrix', ds, 'ds is: ');
            toolkit('matrix', vel, 'vel is: ');
            toolkit('matrix', dq, 'dq is: ');
            toolkit('matrix', t, 't is: ');
            toolkit('matrix', delta_L, 'dL is: ');
        end
        COMPILE = 1;
    else
        success = 0;
        break;
    end
    i = i + 1;
end
T = i;
H = zeros(1,T);
if success
     % compute x_path(:, i) to make rank same to q_path
     [~, ~, ra, pa, ~, ~] = Jacobi(q_path(:, i), robot);
     X_path(:, i) = matrix2pose(ra(:, :, n+1), pa(:, n+1));
     if ~(obstacleFree([X_path(1:3,i) pa(1:3, 4, :)], obstacle)  ...
            && boundaryFree(q_path(:, i), q_max, q_min))
        success = 0;
        return
     else
         X_init = X_path(:, 1);
         X_goal = X_init + L*Euler_v;
         bias = rrtDistance(X_goal, X_path(:, i));
         if allow_error < bias
             success = 0;
             return
         end
    end
    %求解目标函数H(x)
    sq = zeros(n,1);
    q_norm = pi;
    for j = 1:T
        for i = 1:n
            if q_max(i,1) - q_path(i,j) < q_norm || q_path(i,j) - q_min(i,1) < q_norm
                sq(i,1) = 1/4*(q_max(i,1)-q_min(i,1))^2/((q_max(i,1)-q_path(i,j))...
                    *(q_path(i,j)-q_min(i,1)));
            else
                sq(i,1)=0;
            end
        end
        H(1,j) = sum(sq);
    end
    H = H / double(n);
end
end