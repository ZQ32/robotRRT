function [output_q, output_Xfree, output_T, success] = RRT_NP(q0, ...
    X_max, X_min, rE_goal, RE_goal, obstacle)
% 基于工作自由空间的RRT法进行机械臂轨迹规划，逆解使用newton-raphson算法
% 输入变量：
% q0:机械臂初始关节角
% key:表示末端变量的限制情况，若key(i)=0,表示末端第i个变量固定不动；若key(i)=1,
% 表示末端第i个变量运动自由
% X_max,X_min:分别表示工作空间的最大最小边界
% X_goal:表示末端目标位姿(x,y,z,alpha,beta,gamma),前三者是坐标，后三者为三个
% Euler角,在下面用到
% rE_goal:末端位置[x, y, z]
% RE_goal:表示末端目标姿态矩阵，3x3矩阵，角度变换采用Euler ZXZ变换，同
% X_goal。
% obstacle：障碍物

% 输出变量：
% Outputq:规划好的关节角序列
% OutputT:规划好的时间序列
% OutputX:规划好的末端位置序列
% OutputRE:规划好的末端位姿序列

% define global variables
global COMPILE;
global SHOW_DIAGRAM;
% read in robot data
robot = load('robotDH.mat');
n = robot.n;
m = robot.m;
% 载入机械臂参数
% 其中：
% d,a,alpha为DH参数
% d(i)从x_i-1到x_i轴沿z_i-1轴的距离；
% a(i)从z_i-1到z_i沿x_i的距离；
% alpha(i)从z_i-1到z_i绕x_i的夹角(按右手规则)
% theta(i)为从x_i-1到x_i绕z_i-1的夹角(按右手规则),为自由变量,初始值均假定为0
% q_max、q_min为关节变量的上下限
% n为关节角数量，即自由度数
% m为位姿变量

% initialize
% K规划总数
K = 1000; 
q_path = zeros(n, K);
X_free = zeros(m, K);
parent = zeros(1, K);
cost = zeros(1, K);
Time = zeros(1, K);
% compute the pose of the end point
X_goal = zeros(m, 1);
X_goal(1:6) = matrix2pose(RE_goal, rE_goal);
% compute the pose of the initial point
q_path(:, 1) = q0;
[~, ~, R0, P0, ~, ~] = Jacobi(q0, robot);
X_free(1:6, 1) = matrix2pose(R0(:, :, n+1), P0(:, n+1));
% draw the goal and initial point
if SHOW_DIAGRAM
    subplot(331);
    plot3(X_goal(1), X_goal(2), X_goal(3), 'b+');
    hold on;
    plot3(X_free(1, 1), X_free(2, 1), X_free(3, 1), 'gd');
    hold on;
    subplot(332);
    plot3(X_goal(4), X_goal(5), X_goal(6), 'b+');
    hold on;
    plot3(X_free(4, 1), X_free(5, 1), X_free(6, 1), 'gd');
    hold on;
end
% numTree take down the current number of point in the tree
numTree = 1;
% inializition and target position obstacle detection and boundary detection
i = 1; % the iterator variable
% factor and connect
factor = max(abs(X_max-X_min));
connect = 0;
endPoint = zeros(1, K); % take donw the points which near to goal
rank_end = 0; % the current length of endPoint array
num_fail = 0; % the total times fail between while
% test if initial and goal point is in collision with obstacle or boundary
if obstacleFree(P0, obstacle) && boundaryFree(X_free, X_max, X_min)...
        && obstacleFree(X_goal, obstacle) ...
        && boundaryFree(X_goal, X_max, X_min)
    i = i+1;
    num_fail = 1;
    rank_end = rank_end + 1;
else
    i = K+1;
end
while i <= K && num_fail <= 5*K
   % sample function, random point in free space
%    X_rand = sample(X_min, X_max); 
    X_rand = X_goal;
   if obstacleFree(X_rand, obstacle)
       if COMPILE
           toolkit('matrix', i, 'current rank i is: ');
           toolkit('matrix', num_fail, 'num_fail is: ');
       end
       % doing extend here, generate new tree point and added it to 
       % the original tree
        [q_path, X_free, parent, cost, Time, success] = extendNP(q_path, ...
            X_free, parent, cost, Time, X_rand, numTree+1, factor, ...
            obstacle, robot);
        COMPILE = 0;
        if COMPILE
            if success
                toolkit('array', i, 'current rank is: ');
                toolkit('array', X_goal(:), 'the goal point is: ');
                toolkit('array', X_free(:, 1), 'the initial point is: ');
                toolkit('array', q_path(:, i), 'the new point is: ');
                toolkit('array', X_free(:, i), 'the new pointx is: ');
                toolkit('array', X_rand(:), 'the rand point is: ');
                toolkit('input');
            else
                disp('extend not success');
            end
        end
        COMPILE = 1;
        if success
            % draw the rand point, new point to the graph
            if SHOW_DIAGRAM
                subplot(331);
                plot3(real(X_free(1, :)), real(X_free(2, :)), ...
                    real(X_free(3, :)), 'r*');
                axis('equal');
                axis([-1, 1, -1, 1, 0, 1.5]);
                title('X_free');
                hold on;
                subplot(332);
                plot3(X_free(4, :), X_free(5, :), X_free(6, :), 'r.');
                hold on;
            end
            % numTree change to i, means there are i points in the tree
            numTree = i;
            length = rrtDistance(X_goal, X_free(:, i));
%             if COMPILE
%                 toolkit('matrix', length, 'current distance is: ');
%             end
            % if length is close enough, then get the answer and quit,
            % changing succ to 1, perform MLG to get the last answer
            succ = 0;
            if length < 0.3
                steps = max(5, double(int32(100*length)));
                time = double(int32(steps/5));
                [~, X_p, ~, succ, q_iter, x_iter, t_iter] = ...
                    newton_smooth(q_path(:, i), X_goal, steps, ...
                    obstacle, robot, time);
                if succ
                    t_iter = t_iter + Time(i);
                end
            end
            % connect to c++ process, only one solution is enough
            connect = 0;
            if succ && goalTest(X_p, X_goal)
                connect = 1;
                endPoint(rank_end) = i;
                rank_end = rank_end + 1;
                break;
            end
            if goalTest(X_free(:,i), X_goal) && rank_end <= int8(K/10)
                endPoint(rank_end) = i;
                rank_end = rank_end + 1;
            end
            i = i + 1;
        else
            num_fail = num_fail + 1;
        end
   else
       num_fail = num_fail + 1;
   end
end

if 1 < rank_end
    success = 1;
    % find path from q0 to goal in the tree
    nendPoint = endPoint(1 : rank_end-1);
    [optimal_q, optimal_Xfree, optimal_T] = findPath(q_path, X_free, ...
        parent, cost, Time, nendPoint, K);
    if connect
        optimal_q = [optimal_q q_iter];
        optimal_Xfree = [optimal_Xfree x_iter];
        optimal_T = [optimal_T t_iter];
    end
    % smooth the path
    [output_q, output_Xfree, output_T] = smooth(optimal_q, ...
        optimal_Xfree, optimal_T);
else
    success = 0;
    output_q = q_path(:, 1);
    output_Xfree = X_free(:, 1);
    output_T = 0;
end
end